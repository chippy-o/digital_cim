`timescale 1ns / 1ps
// ============================================================================
// sum_buffer : pipeline register between the adder trees and the shifters
//
//   adder_tree_32[j].sum  --> sum_in[j]   (captured every clock)
//   sum_out[j]            --> shifter[j].partial_sum
//
// - One COLS-wide bank of W-bit registers (default 32 x 13 = 416 flops).
// - Free-running: loads every cycle, no enable, no reset.
//   The FSM gates the accumulators with acc_en (delayed 1 cycle), so the
//   contents are ignored until the first real bit-plane sum has landed.
//   Dropping the reset saves area and removes a reset-fanout net.
// - Latency: exactly 1 clock.
// ============================================================================
module sum_buffer #(
    parameter int COLS = 32,
    parameter int W    = 13
)(
    input  logic                clk,
    input  logic signed [W-1:0] sum_in  [0:COLS-1],
    output logic signed [W-1:0] sum_out [0:COLS-1]
);

    always_ff @(posedge clk) begin
        for (int j = 0; j < COLS; j++)
            sum_out[j] <= sum_in[j];
    end

endmodule
