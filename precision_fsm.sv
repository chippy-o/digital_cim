module fsm_controller (
    input  logic       clk,
    input  logic       rst,
    input  logic       start,
    input  logic [1:0] precision,

    output logic       weight_we,
    output logic [4:0] weight_row,
    output logic       act_we,
    output logic [2:0] bit_index,
    output logic       acc_clear,
    output logic       acc_en,
    output logic       out_we,
    output logic       done
);

    // FSM states
    typedef enum logic [2:0] {
        IDLE,
        LOAD_WEIGHTS,
        LOAD_ACTIVATIONS,
        CLEAR_ACC,
        COMPUTE,
        WRITE_OUTPUT,
        DONE
    } state_t;

    // State registers
    state_t current_state;
    state_t next_state;

    // Internal counters
    logic [4:0] weight_count; //which weight row is being loaded
    logic [2:0] bit_count; //which activation bit is being processed

    //combinational logic
always_comb @ (posedge clk) begin
    next_state=current_state;
    case(current_state)
    IDLE: begin
        if(start)
        next_state=LOAD_WEIGHTS;
        else
            next_state=IDLE;
    end

    LOAD_WEIGHTS: begin
        if (weight_count==5'd31)
        next_state=LOAD_ACTIVATIONS;
        else
            next_state=LOAD_WEIGHTS;

    end

    LOAD_ACTIVATIONS: begin
        //only 1 cycle cos act data ip is 32 bit itself
        next_state=CLEAR_ACC;
    end

    CLEAR_ACC: begin
        next_state=COMPUTE;
    end

    COMPUTE: begin
    if ((precision == 2'b00 && bit_count == 3'd1) ||
        (precision == 2'b01 && bit_count == 3'd3) ||
        (precision == 2'b10 && bit_count == 3'd7))
        next_state = WRITE_OUTPUT;
    else
        next_state = COMPUTE;
end
endcase
    
end


endmodule