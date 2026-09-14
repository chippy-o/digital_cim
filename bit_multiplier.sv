module bit_multiplier_32 (
    input  logic              activation_bits [0:31],
    input  logic signed [7:0] weights         [0:31],
    output logic signed [7:0] partial_products[0:31]
);

    always_comb begin
        // Declaring 'i' inside the for-loop is safer and standard in SystemVerilog
        for (int i = 0; i < 32; i = i + 1) begin
            // Inline ternary operator acts as a clean 2-to-1 MUX
            partial_products[i] = activation_bits[i] ? weights[i] : 8'sd0;
        end
    end

endmodule
