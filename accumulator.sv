`timescale 1ns / 1ps

module accumulator (
    input  logic               clk,
    input  logic               rst,

    input  logic               acc_clear,
    input  logic               acc_en,
    input logic acc_sub,

    input  logic signed [20:0] shifted_sum,

    output logic signed [20:0] accumulated_result
);

    always_ff @(posedge clk) begin
    if (rst || acc_clear) begin
        accumulated_result <= '0;
    end
    else if (acc_en) begin
        if (acc_sub)
            accumulated_result <= accumulated_result - shifted_sum;
        else
            accumulated_result <= accumulated_result + shifted_sum;
    end
end


endmodule

