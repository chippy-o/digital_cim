`timescale 1ns / 1ps

module accumulator (
    input  logic               clk,
    input  logic               rst,

    input  logic               acc_clear,
    input  logic               acc_en,

    input  logic signed [20:0] shifted_sum,

    output logic signed [20:0] accumulated_result
);

    always_ff @(posedge clk) begin
        if (rst) begin
            accumulated_result <= 21'sd0;
        end
        else if (acc_clear) begin
            accumulated_result <= 21'sd0;
        end
        else if (acc_en) begin
            accumulated_result <= accumulated_result + shifted_sum;
        end
    end

endmodule

