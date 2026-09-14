module adder_tree_32 (
    input  logic signed [7:0] pp [0:31],
    output logic signed [12:0] sum
);

    // Level 1: 32 -> 16
    logic signed [8:0] sum_l1 [0:15];

    // Level 2: 16 -> 8
    logic signed [9:0] sum_l2 [0:7];

    // Level 3: 8 -> 4
    logic signed [10:0] sum_l3 [0:3];

    // Level 4: 4 -> 2
    logic signed [11:0] sum_l4 [0:1];

    // Level 5: 2 -> 1
    logic signed [12:0] sum_l5;

    integer i;

    always_comb begin

        // -------------------------
        // Level 1: 32 -> 16
        // -------------------------
        for (i = 0; i < 16; i = i + 1) begin
            sum_l1[i] = $signed(pp[2*i])
                       + $signed(pp[2*i+1]);
        end

        // -------------------------
        // Level 2: 16 -> 8
        // -------------------------
        for (i = 0; i < 8; i = i + 1) begin
            sum_l2[i] = $signed(sum_l1[2*i])
                       + $signed(sum_l1[2*i+1]);
        end

        // -------------------------
        // Level 3: 8 -> 4
        // -------------------------
        for (i = 0; i < 4; i = i + 1) begin
            sum_l3[i] = $signed(sum_l2[2*i])
                       + $signed(sum_l2[2*i+1]);
        end

        // -------------------------
        // Level 4: 4 -> 2
        // -------------------------
        for (i = 0; i < 2; i = i + 1) begin
            sum_l4[i] = $signed(sum_l3[2*i])
                       + $signed(sum_l3[2*i+1]);
        end

        // -------------------------
        // Level 5: 2 -> 1
        // -------------------------
        sum_l5 = $signed(sum_l4[0])
               + $signed(sum_l4[1]);

        sum = sum_l5;
    end

endmodule