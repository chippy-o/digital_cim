# ============================================================================
# sim.do : compile + simulate dcim_tb in ModelSim / Questa, with a focused wave
#
# Usage (ModelSim transcript window):
#   cd <folder that has all the .sv files>
#   do sim.do
#
# Re-run after editing RTL: just "do sim.do" again.
# ============================================================================

quit -sim
if {[file exists work]} { vdel -lib work -all }
vlib work
vmap work work

# ---------------- compile ----------------
# -timescale gives a default to files that have no `timescale line
# NOTE: do NOT also compile precision_fsm.sv if it contains a second
#       "module fsm_controller" (duplicate module error).
vlog -sv -timescale 1ns/1ps \
    activation_buffer.sv \
    weight_array.sv \
    bit_multiplier.sv \
    adder_tree.sv \
    sum_buffer.sv \
    shift_sign_align.sv \
    accumulator.sv \
    Requantization.sv \
    output_buffer.sv \
    fsm_controller.sv \
    dcim_top.sv \
    dcim_tb.sv

# ---------------- simulate ----------------
# +acc keeps internal signals visible for the waveform
vsim -voptargs=+acc work.dcim_tb

# ---------------- waveform ----------------
configure wave -signalnamewidth 1
configure wave -timelineunits ns

# Test status: which test is running, pass/fail counters
add wave -noupdate -divider {TEST STATUS}
add wave -noupdate -radix unsigned            /dcim_tb/test_num
add wave -noupdate -radix ascii               /dcim_tb/test_name
add wave -noupdate -radix unsigned            /dcim_tb/err_count
add wave -noupdate -radix unsigned            /dcim_tb/tests_passed
add wave -noupdate -radix unsigned            /dcim_tb/tests_failed

# Host interface
add wave -noupdate -divider {HOST}
add wave -noupdate                            /dcim_tb/clk
add wave -noupdate                            /dcim_tb/rst
add wave -noupdate                            /dcim_tb/start
add wave -noupdate                            /dcim_tb/load_weights
add wave -noupdate -radix binary              /dcim_tb/precision
add wave -noupdate -radix unsigned            /dcim_tb/shift_amount
add wave -noupdate                            /dcim_tb/busy
add wave -noupdate                            /dcim_tb/done

# FSM
add wave -noupdate -divider {FSM}
add wave -noupdate                            /dcim_tb/dut/u_fsm/state
add wave -noupdate -radix binary              /dcim_tb/dut/u_fsm/prec_reg
add wave -noupdate -radix unsigned            /dcim_tb/dut/u_fsm/last_plane
add wave -noupdate                            /dcim_tb/dut/u_fsm/load_done
add wave -noupdate                            /dcim_tb/dut/u_fsm/compute_done

# LOAD stage
add wave -noupdate -divider {LOAD}
add wave -noupdate                            /dcim_tb/dut/weight_we
add wave -noupdate -radix unsigned            /dcim_tb/dut/weight_row
add wave -noupdate -radix decimal             /dcim_tb/weight_row_data[0]
add wave -noupdate                            /dcim_tb/dut/act_we
add wave -noupdate -radix hexadecimal         /dcim_tb/activation_data[0]

# COMPUTE stage (front of pipeline), column 0
add wave -noupdate -divider {COMPUTE (front)}
add wave -noupdate -radix unsigned            /dcim_tb/dut/bit_index
add wave -noupdate                            /dcim_tb/dut/act_bit[0]
add wave -noupdate -radix decimal             /dcim_tb/dut/weights[0][0]
add wave -noupdate -radix decimal             /dcim_tb/dut/col_sum[0]

# Pipeline register + POST_COMPUTE stage, column 0
add wave -noupdate -divider {PIPELINE / ACCUMULATE}
add wave -noupdate -radix decimal             /dcim_tb/dut/col_sum_q[0]
add wave -noupdate -radix unsigned            /dcim_tb/dut/bit_index_d
add wave -noupdate -radix decimal             /dcim_tb/dut/col_shifted[0]
add wave -noupdate                            /dcim_tb/dut/acc_clear
add wave -noupdate                            /dcim_tb/dut/acc_en
add wave -noupdate                            /dcim_tb/dut/acc_sub
add wave -noupdate -radix decimal             /dcim_tb/dut/col_acc[0]
add wave -noupdate -radix decimal             /dcim_tb/dot_ref[0]

# OUTPUT stage, column 0 (+ whole output vector)
add wave -noupdate -divider {OUTPUT}
add wave -noupdate -radix decimal             /dcim_tb/dut/col_q[0]
add wave -noupdate                            /dcim_tb/dut/out_we
add wave -noupdate -radix decimal             /dcim_tb/output_data[0]
add wave -noupdate -radix decimal             /dcim_tb/q_ref[0]
add wave -noupdate -radix decimal             /dcim_tb/output_data

update

# ---------------- run ----------------
run -all
wave zoom full
