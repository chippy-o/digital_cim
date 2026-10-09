`timescale 1ns / 1ps

// ============================================================================
// D-CIM FSM controller
// Flow: IDLE -> LOAD -> COMPUTE -> POST_COMPUTE -> DONE -> IDLE
//
// precision: 00 = INT8, 01 = INT4, 10 = INT2, 11 = INT8
//
// Pipeline (sum_buffer sits between adder trees and shifters):
//   bit_index                       -> activation_buffer   (front, not delayed)
//   bit_index_d, acc_en, acc_sub    -> shifters/accumulators (delayed 1 cycle)
// ============================================================================

module fsm_controller (
    input  logic       clk,
    input  logic       rst,
    input  logic       start,
    input  logic       load_weights,   // sampled with start: 1 = reload all 32 weight rows
    input  logic [1:0] precision,

    output logic       weight_we,
    output logic [4:0] weight_row,
    output logic       act_we,
    output logic [2:0] bit_index,      // -> activation_buffer
    output logic [2:0] bit_index_d,    // -> shifters (delayed to match sum_buffer)
    output logic       acc_clear,
    output logic       acc_en,         // delayed to match sum_buffer
    output logic       acc_sub,        // delayed, high on the sign plane
    output logic       out_we,
    output logic       done,
    output logic       busy
);

    // FSM states
    typedef enum logic [2:0] {
        IDLE,
        LOAD,
        COMPUTE,
        POST_COMPUTE,
        DONE
    } state_t;

    // State registers
    state_t state;
    state_t next_state;

    // Internal counters
    logic [4:0] weight_count; //which weight row is being loaded
    logic [2:0] bit_count;    //which activation bit is being processed

    // Settings captured at start (stable for the whole run)
    logic [1:0] prec_reg;
    logic       load_w_reg;

    // Decoded conditions
    logic [2:0] last_plane;   //n-1, also the sign-plane index
    logic       load_done;    //last LOAD cycle
    logic       compute_done; //last COMPUTE cycle

    //last plane decode
always_comb begin
    case (prec_reg)
        2'b01:   last_plane = 3'd3;  // INT4
        2'b10:   last_plane = 3'd1;  // INT2
        default: last_plane = 3'd7;  // INT8
    endcase
end

assign load_done    = (!load_w_reg) || (weight_count == 5'd31);
assign compute_done = (bit_count == last_plane);

    //combinational logic
always_comb begin
    next_state=state;
    case(state)
    IDLE: begin
        if(start)
            next_state=LOAD;
        else
            next_state=IDLE;
    end

    LOAD: begin
        if (load_done)
            next_state=COMPUTE;
        else
            next_state=LOAD;
    end

    COMPUTE: begin
        if (compute_done)
            next_state = POST_COMPUTE;
        else
            next_state = COMPUTE;
    end

    POST_COMPUTE: begin
        next_state=DONE;
    end

    DONE: begin
        next_state=IDLE;
    end

    default:
        next_state=IDLE;

endcase

end

//sequential logic:
always_ff @(posedge clk) begin

    if (rst) begin
        state        <= IDLE;
        weight_count <= 5'd0;
        bit_count    <= 3'd0;
        prec_reg     <= 2'b00;
        load_w_reg   <= 1'b0;
        done         <= 1'b0;
    end

    else begin

        // State update
        state <= next_state;

        // New operation: capture settings
        if (state == IDLE && start) begin
            prec_reg   <= precision;
            load_w_reg <= load_weights;
        end

        // Weight row counter (counts only while loading weights, cleared otherwise)
        if (state == LOAD && !load_done)
            weight_count <= weight_count + 5'd1;
        else
            weight_count <= 5'd0;

        // Compute bit counter (cleared on leaving COMPUTE)
        if (state == COMPUTE && !compute_done)
            bit_count <= bit_count + 3'd1;
        else
            bit_count <= 3'd0;

        // done one cycle after out_we, when output_data is valid
        done        <= (state == DONE);

    end

end

//pipeline-aligned controls:
//one flop each = one stage, same clock edge as sum_buffer.
//add one more flop to each if another pipeline stage is added.

// acc_en: accumulate while the plane in sum_buffer is valid
always_ff @(posedge clk) begin
    if (rst)
        acc_en <= 1'b0;
    else
        acc_en <= (state == COMPUTE);
end

// acc_sub: subtract when the sign plane is in sum_buffer
always_ff @(posedge clk) begin
    if (rst)
        acc_sub <= 1'b0;
    else
        acc_sub <= (state == COMPUTE) && compute_done;
end

// bit_index_d: shift amount for the plane in sum_buffer
always_ff @(posedge clk) begin
    if (rst)
        bit_index_d <= 3'd0;
    else
        bit_index_d <= bit_count;
end

//output logic:
assign weight_we  = (state == LOAD) && load_w_reg;
assign weight_row = weight_count;
assign act_we     = (state == LOAD) && load_done;   // last LOAD cycle
assign bit_index  = bit_count;
assign acc_clear  = (state == IDLE) || (state == LOAD);
assign out_we     = (state == DONE);
assign busy       = (state != IDLE);

endmodule
