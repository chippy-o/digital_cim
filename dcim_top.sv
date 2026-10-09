`timescale 1ns / 1ps

// ============================================================================
// dcim_top : register-based reconfigurable digital CIM accelerator
//
// Array    : 32 input channels (rows, i) x 32 output columns (j), INT8 weights
// Inputs   : 32 activations, INT8 / INT4 / INT2 (bit-serial, LSB first)
// Output   : 32 requantized INT8 results
//
// Datapath per column j:
//   activation_buffer -> bit_multiplier_32 -> adder_tree_32 -> [sum_buffer]
//   -> shifter -> accumulator -> Requantization -> output_buffer
//
// Control (fsm_controller):
//   bit_index                    -> activation_buffer   (front of pipeline)
//   bit_index_d, acc_en, acc_sub -> shifters / accumulators (1 cycle later,
//                                   aligned with sum_buffer)
//
// Host protocol:
//   1. Pulse start for one cycle with precision, load_weights, shift_amount.
//      Keep activation_data valid until busy rises; keep shift_amount stable
//      until done.
//   2. If load_weights = 1, present weight_row_data = row[weight_row] while
//      busy (the FSM steps weight_row 0..31, one row per cycle).
//   3. output_data is valid when done = 1 (1-cycle pulse) and holds until the
//      next run.
//
// precision: 00 = INT8, 01 = INT4, 10 = INT2, 11 = INT8
// ============================================================================

module dcim_top (
    input  logic              clk,
    input  logic              rst,

    // Command
    input  logic              start,
    input  logic              load_weights,
    input  logic        [1:0] precision,
    input  logic        [3:0] shift_amount,

    // Weight load (one row per cycle, row selected by weight_row)
    input  logic signed [7:0] weight_row_data [0:31],
    output logic        [4:0] weight_row,

    // Activations (INT4/INT2: two's complement value in the low n bits)
    input  logic        [7:0] activation_data [0:31],

    // Result
    output logic signed [7:0] output_data [0:31],
    output logic              done,
    output logic              busy
);

    // ------------------------------------------------------------------------
    // Control signals (fsm_controller -> datapath)
    // ------------------------------------------------------------------------
    logic       weight_we;
    logic       act_we;
    logic [2:0] bit_index;      // -> activation_buffer
    logic [2:0] bit_index_d;    // -> shifters (delayed)
    logic       acc_clear;
    logic       acc_en;         // delayed
    logic       acc_sub;        // delayed
    logic       out_we;

    // ------------------------------------------------------------------------
    // Datapath wires
    // ------------------------------------------------------------------------
    wire signed [7:0]  weights     [0:31][0:31]; // [i = input channel][j = column]
    wire               act_bit     [0:31];       // selected bit-plane of all 32 activations
    wire signed [12:0] col_sum     [0:31];       // adder tree outputs
    wire signed [12:0] col_sum_q   [0:31];       // sum_buffer outputs
    wire signed [20:0] col_shifted [0:31];       // shifter outputs
    wire signed [20:0] col_acc     [0:31];       // accumulator outputs
    wire signed [7:0]  col_q       [0:31];       // requantized outputs

    // ------------------------------------------------------------------------
    // Controller
    // ------------------------------------------------------------------------
    fsm_controller u_fsm (
        .clk          (clk),
        .rst          (rst),
        .start        (start),
        .load_weights (load_weights),
        .precision    (precision),
        .weight_we    (weight_we),
        .weight_row   (weight_row),
        .act_we       (act_we),
        .bit_index    (bit_index),
        .bit_index_d  (bit_index_d),
        .acc_clear    (acc_clear),
        .acc_en       (acc_en),
        .acc_sub      (acc_sub),
        .out_we       (out_we),
        .done         (done),
        .busy         (busy)
    );

    // ------------------------------------------------------------------------
    // Storage
    // ------------------------------------------------------------------------
    weight_array u_weight_array (
        .clk             (clk),
        .rst             (rst),
        .weight_we       (weight_we),
        .weight_row      (weight_row),
        .weight_row_data (weight_row_data),
        .weights         (weights)
    );

    activation_buffer u_activation_buffer (
        .clk               (clk),
        .rst               (rst),
        .act_we            (act_we),
        .i_bit_index       (bit_index),
        .activation_data   (activation_data),
        .o_activation_bits (act_bit)
    );

    // ------------------------------------------------------------------------
    // 32 compute columns
    // ------------------------------------------------------------------------
    genvar i, j;
    generate
        for (j = 0; j < 32; j++) begin : col

            // Column j's 32 weights (transpose: weights[i][j] for all i)
            wire signed [7:0] w_col [0:31];
            wire signed [7:0] pp    [0:31];

            for (i = 0; i < 32; i++) begin : w_tap
                assign w_col[i] = weights[i][j];
            end

            // In-memory multiply: activation bit AND weight
            bit_multiplier_32 u_mult (
                .activation_bits  (act_bit),
                .weights          (w_col),
                .partial_products (pp)
            );

            // 32 -> 1 reduction
            adder_tree_32 u_tree (
                .pp  (pp),
                .sum (col_sum[j])
            );

            // (sum_buffer sits here, instantiated below for all columns)

            // Bit-plane weighting: << bit_index_d
            shifter u_shift (
                .partial_sum (col_sum_q[j]),
                .i_bit_index (bit_index_d),
                .shifted_sum (col_shifted[j])
            );

            // Add / subtract (sign plane) accumulate
            accumulator u_acc (
                .clk                (clk),
                .rst                (rst),
                .acc_clear          (acc_clear),
                .acc_en             (acc_en),
                .acc_sub            (acc_sub),
                .shifted_sum        (col_shifted[j]),
                .accumulated_result (col_acc[j])
            );

            // Round, shift, saturate to INT8
            Requantization u_requant (
                .accumulated_result (col_acc[j]),
                .shift_amount       (shift_amount),
                .quantized_output   (col_q[j])
            );

        end
    endgenerate

    // ------------------------------------------------------------------------
    // Pipeline register between adder trees and shifters (all 32 columns)
    // ------------------------------------------------------------------------
    sum_buffer #(
        .COLS (32),
        .W    (13)
    ) u_sum_buffer (
        .clk     (clk),
        .sum_in  (col_sum),
        .sum_out (col_sum_q)
    );

    // ------------------------------------------------------------------------
    // Output register
    // ------------------------------------------------------------------------
    output_buffer u_output_buffer (
        .clk            (clk),
        .rst            (rst),
        .out_we         (out_we),
        .quantized_data (col_q),
        .output_data    (output_data)
    );

endmodule
