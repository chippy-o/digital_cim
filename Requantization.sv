`timescale 1ns / 1ps

module Requantization (
    input  logic signed [20:0] accumulated_result,
    // Valid range 0 to 15. A 21-bit accumulator never needs more than ~12
    // to reach INT8, and shifts of 22 or more would overflow the 22-bit
    // rounding constant below.
    input  logic        [3:0]  shift_amount,

    output logic signed [7:0]  quantized_output
);

    logic signed [21:0] rounded_value;
    logic signed [21:0] shifted_value;

    always_comb begin

        // ------------------------------------------------
        // 1. Rounding
        // Add 2^(shift_amount-1) before right shifting
        // ------------------------------------------------
        if (shift_amount == 0) begin
            rounded_value = $signed(accumulated_result);
        end
        else begin
            rounded_value =
                $signed(accumulated_result) +
                (22'sd1 <<< (shift_amount - 1));
        end

        // ------------------------------------------------
        // 2. Arithmetic right shift
        // ------------------------------------------------
        shifted_value = rounded_value >>> shift_amount;

        // ------------------------------------------------
        // 3. INT8 saturation
        // Range = -128 to +127
        // ------------------------------------------------
        if (shifted_value > 22'sd127) begin
            quantized_output = 8'sd127;
        end
        else if (shifted_value < -22'sd128) begin
            quantized_output = -8'sd128;
        end
        else begin
            quantized_output = shifted_value[7:0];
        end

    end

endmodule