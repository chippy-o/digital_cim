module shifter (
    input  logic signed [12:0] partial_sum,
    input  logic        [2:0]  i_bit_index,

    output logic signed [20:0] shifted_sum
);

    always_comb begin
        shifted_sum = $signed(partial_sum) <<< i_bit_index;
    end

endmodule
