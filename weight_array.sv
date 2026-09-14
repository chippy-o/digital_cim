module weight_array (
    input  logic              clk,
    input  logic              rst,

    // Weight loading interface
    input  logic              weight_we,
    input  logic        [4:0] weight_row,
    input  logic signed [7:0] weight_row_data [0:31],

    // Stored weights
    output logic signed [7:0] weights [0:31][0:31]
);

    // 32 × 32 array of 8-bit registers
    logic signed [7:0] dff [0:31][0:31];

    integer i;

    // Weight loading
    always_ff @(posedge clk) begin

        if (rst) begin
            // Clear all 1024 registers
            for (i = 0; i < 32; i = i + 1)
                for (integer j = 0; j < 32; j = j + 1)
                    dff[i][j] <= '0;
        end

        else if (weight_we) begin
            // Load one complete row
            for (i = 0; i < 32; i = i + 1)
                dff[weight_row][i] <= weight_row_data[i];

                /*
                weight loading fashion:
            
                dff[weight_row][0]  <= weight_row_data[0];
                dff[weight_row][1]  <= weight_row_data[1];
                dff[weight_row][2]  <= weight_row_data[2];
                ...
                dff[weight_row][31] <= weight_row_data[31];

                */
        end

    end

    // Make stored weights available to compute datapath
    assign weights = dff;

endmodule