`timescale 1ns / 1ps

module activation_buffer (
    input  logic              clk,
    input  logic              rst,
    input  logic              act_we,

    // Bit number selected by FSM: 0 to 7
    input  logic [2:0]        i_bit_index,

    // 32 activation values, each 8 bits
    input  logic [7:0]        activation_data [0:31],

    // One selected bit from each of the 32 activations
    output logic              o_activation_bits [0:31]
);

    // Storage: 32 activations × 8 bits
    logic [7:0] activation_store [0:31];

    integer i;
    integer j;

    // Store activations
    always_ff @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < 32; i = i + 1) begin
                activation_store[i] <= 8'd0;
            end
        end
        else if (act_we) begin
            for (i = 0; i < 32; i = i + 1) begin
                activation_store[i] <= activation_data[i];
            end
        end
    end

    // Select one bit from every activation
    always_comb begin
        for (j = 0; j < 32; j = j + 1) begin
            o_activation_bits[j] =
                activation_store[j][i_bit_index];
        end
    end

endmodule