`timescale 1ns / 1ps

module output_buffer (
    input  logic               clk,
    input  logic               rst,

    input  logic               out_we,

    input  logic signed [7:0]  quantized_data [0:31],
    output logic signed [7:0]  output_data    [0:31]
);

    integer i;

    always_ff @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < 32; i = i + 1) begin
                output_data[i] <= 8'sd0;
            end
        end
        else if (out_we) begin
            for (i = 0; i < 32; i = i + 1) begin
                output_data[i] <= quantized_data[i];
            end
        end
    end

endmodule
