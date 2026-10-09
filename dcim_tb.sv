`timescale 1ns / 1ps

// ============================================================================
// dcim_tb : self-checking testbench for dcim_top
//
// Every run is checked against a reference model on three levels:
//   1. raw 21-bit accumulator of every column  == exact dot product
//   2. output_data of every column             == round/shift/saturate(dot)
//   3. latency  start -> done                  == expected cycle count
// Protocol monitors run all the time:
//   - acc_en and out_we never high together
//   - weight_we / act_we only while busy
//   - done is a 1-cycle pulse
//
// Transcript: one PASS/FAIL line per test, details on failure, summary at end.
// Waveform  : test_num / test_name / err_count show which test is running.
//
// precision: 00 = INT8, 01 = INT4, 10 = INT2, 11 = INT8
// ============================================================================

module dcim_tb;

    // ------------------------------------------------------------------------
    // Clock / DUT signals
    // ------------------------------------------------------------------------
    localparam real CLK_PERIOD = 10.0;  // 100 MHz in simulation (timing is cycle based)

    logic              clk;
    logic              rst;
    logic              start;
    logic              load_weights;
    logic        [1:0] precision;
    logic        [3:0] shift_amount;
    logic signed [7:0] weight_row_data [0:31];
    logic        [4:0] weight_row;
    logic        [7:0] activation_data [0:31];
    wire  signed [7:0] output_data     [0:31];
    wire               done;
    wire               busy;

    dcim_top dut (
        .clk             (clk),
        .rst             (rst),
        .start           (start),
        .load_weights    (load_weights),
        .precision       (precision),
        .shift_amount    (shift_amount),
        .weight_row_data (weight_row_data),
        .weight_row      (weight_row),
        .activation_data (activation_data),
        .output_data     (output_data),
        .done            (done),
        .busy            (busy)
    );

    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // ------------------------------------------------------------------------
    // Reference model storage
    // ------------------------------------------------------------------------
    logic signed [7:0]  W_ref   [0:31][0:31];   // [i = input channel][j = column]
    logic signed [7:0]  X_ref   [0:31];         // activations (signed value)
    longint             dot_ref [0:31];         // exact dot product per column
    logic signed [7:0]  q_ref   [0:31];         // expected output_data

    // Host weight-load model: present the row the FSM asks for
    always_comb begin
        for (int j = 0; j < 32; j++)
            weight_row_data[j] = W_ref[weight_row][j];
    end

    // ------------------------------------------------------------------------
    // Status (visible in the waveform)
    // ------------------------------------------------------------------------
    int                test_num;
    logic [8*24-1:0]   test_name;     // view with radix ASCII
    int                err_count;
    int                run_errors;
    int                tests_passed;
    int                tests_failed;
    int                cycle;

    always @(posedge clk) cycle <= cycle + 1;

    // ------------------------------------------------------------------------
    // Protocol monitors
    // ------------------------------------------------------------------------
    logic done_q;

    always @(posedge clk) begin
        if (!rst) begin
            if (dut.acc_en && dut.out_we) begin
                $display("[%0t] MONITOR ERROR: acc_en and out_we high together", $time);
                err_count++;
            end
            if ((dut.weight_we || dut.act_we) && !busy) begin
                $display("[%0t] MONITOR ERROR: weight_we/act_we while not busy", $time);
                err_count++;
            end
            if (done && done_q) begin
                $display("[%0t] MONITOR ERROR: done high for more than 1 cycle", $time);
                err_count++;
            end
        end
        done_q <= done;
    end

    // ------------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------------
    function automatic int nbits(input logic [1:0] p);
        case (p)
            2'b01:   return 4;
            2'b10:   return 2;
            default: return 8;
        endcase
    endfunction

    function automatic logic signed [7:0] requant(input longint v, input int sh);
        longint r;
        r = (sh == 0) ? v : (v + (64'sd1 <<< (sh - 1)));
        r = r >>> sh;
        if (r > 127)       return 8'sd127;
        else if (r < -128) return -8'sd128;
        else               return r[7:0];
    endfunction

    function automatic logic signed [7:0] rand_in_range(input int lo, input int hi);
        return lo + $urandom_range(hi - lo);
    endfunction

    // Fill weights
    task automatic set_weights(input string mode, input int value = 0);
        for (int i = 0; i < 32; i++)
            for (int j = 0; j < 32; j++)
                case (mode)
                    "const":  W_ref[i][j] = value;
                    "zero":   W_ref[i][j] = 0;
                    default:  W_ref[i][j] = $urandom_range(255);   // full INT8 range
                endcase
    endtask

    // Fill activations for a precision (two's complement in the low n bits)
    task automatic set_acts(input logic [1:0] p, input string mode, input int value = 0);
        int n, lo, hi;
        n  = nbits(p);
        lo = -(1 << (n - 1));
        hi =  (1 << (n - 1)) - 1;
        for (int i = 0; i < 32; i++) begin
            case (mode)
                "const":  X_ref[i] = value;
                "zero":   X_ref[i] = 0;
                "min":    X_ref[i] = lo;
                "max":    X_ref[i] = hi;
                default:  X_ref[i] = rand_in_range(lo, hi);
            endcase
            activation_data[i] = X_ref[i][7:0];
        end
    endtask

    // ------------------------------------------------------------------------
    // One complete run: start -> done, then check everything
    // ------------------------------------------------------------------------
    task automatic run_check(input string name, input logic [1:0] p, input logic lw, input int sh);
        int n, exp_latency, latency, start_cycle, wd;

        test_num++;
        // string -> packed vector (right-aligned, like a string literal)
        test_name = '0;
        for (int k = 0; k < name.len() && k < 24; k++)
            test_name[8*(name.len()-1-k) +: 8] = name[k];
        run_errors = 0;
        n = nbits(p);

        // reference model
        for (int j = 0; j < 32; j++) begin
            dot_ref[j] = 0;
            for (int i = 0; i < 32; i++)
                dot_ref[j] += longint'(X_ref[i]) * longint'(W_ref[i][j]);
            q_ref[j] = requant(dot_ref[j], sh);
        end

        // drive command (change inputs on the falling edge)
        @(negedge clk);
        precision    = p;
        load_weights = lw;
        shift_amount = sh[3:0];
        start        = 1'b1;
        @(posedge clk);
        start_cycle  = cycle;
        @(negedge clk);
        start        = 1'b0;

        // wait for done (with watchdog), sampling on the falling edge
        wd = 0;
        while (done !== 1'b1 && wd < 200) begin
            @(negedge clk);
            wd++;
        end
        if (done !== 1'b1) begin
            $display("[%0t] TIMEOUT in test %0d (%0s)", $time, test_num, name);
            run_errors++;
        end

        latency     = cycle - start_cycle;
        exp_latency = (lw ? 32 : 1) + n + 3;   // LOAD + COMPUTE + POST + DONE + done flop

        if (latency != exp_latency) begin
            $display("    latency: got %0d cycles, expected %0d", latency, exp_latency);
            run_errors++;
        end

        // check every column, at the cycle done is high
        for (int j = 0; j < 32; j++) begin
            if (dut.col_acc[j] !== dot_ref[j][20:0]) begin
                if (run_errors < 4)
                    $display("    col %2d accumulator: got %0d, expected %0d",
                             j, dut.col_acc[j], dot_ref[j]);
                run_errors++;
            end
            if (output_data[j] !== q_ref[j]) begin
                if (run_errors < 4)
                    $display("    col %2d output_data: got %0d, expected %0d (dot %0d, shift %0d)",
                             j, output_data[j], q_ref[j], dot_ref[j], sh);
                run_errors++;
            end
        end

        err_count += run_errors;
        if (run_errors == 0) begin
            tests_passed++;
            $display("[%0t] PASS  test %3d  %-24s INT%0d lw=%0d shift=%2d latency=%0d  col0: dot=%0d out=%0d",
                     $time, test_num, name, n, lw, sh, latency, dot_ref[0], output_data[0]);
        end else begin
            tests_failed++;
            $display("[%0t] FAIL  test %3d  %-24s INT%0d lw=%0d shift=%2d  (%0d errors)",
                     $time, test_num, name, n, lw, sh, run_errors);
        end

        // keep output stable for one cycle in the waveform
        @(negedge clk);
    endtask

    // ------------------------------------------------------------------------
    // Test sequence
    // ------------------------------------------------------------------------
    initial begin
        // init
        rst          = 1'b1;
        start        = 1'b0;
        load_weights = 1'b0;
        precision    = 2'b00;
        shift_amount = 4'd0;
        test_num     = 0;
        test_name    = "reset";
        err_count    = 0;
        tests_passed = 0;
        tests_failed = 0;
        cycle        = 0;
        done_q       = 1'b0;
        set_weights("zero");
        set_acts(2'b00, "zero");

        repeat (5) @(negedge clk);
        rst = 1'b0;
        repeat (2) @(negedge clk);

        $display("=====================================================================");
        $display(" D-CIM testbench start");
        $display("=====================================================================");

        // ---------------- directed: sign-plane alignment ----------------
        // INT8: X0 = -128 (only bit 7 set), W00 = 1 -> result is only the sign plane
        set_weights("zero"); W_ref[0][0] = 1;
        set_acts(2'b00, "zero"); X_ref[0] = -128; activation_data[0] = 8'h80;
        run_check("int8_sign_plane_only", 2'b00, 1'b1, 0);

        // INT4: X0 = -1, W00 = 1 -> +1 +2 +4 -8 = -1
        set_weights("zero"); W_ref[0][0] = 1;
        set_acts(2'b01, "zero"); X_ref[0] = -1; activation_data[0] = 8'h0F;
        run_check("int4_minus_one", 2'b01, 1'b1, 0);

        // INT2: X0 = -2, W00 = 3 -> -6
        set_weights("zero"); W_ref[0][0] = 3;
        set_acts(2'b10, "zero"); X_ref[0] = -2; activation_data[0] = 8'h02;
        run_check("int2_minus_two", 2'b10, 1'b1, 0);

        // ---------------- directed: zeros and extremes ----------------
        set_weights("zero"); set_acts(2'b00, "zero");
        run_check("all_zero", 2'b00, 1'b1, 0);

        set_weights("const", -128); set_acts(2'b00, "min");     // max positive dot = 524288
        run_check("int8_min_x_min", 2'b00, 1'b1, 12);

        set_weights("const", 127); set_acts(2'b00, "min");      // most negative region
        run_check("int8_min_x_max", 2'b00, 1'b1, 12);

        set_weights("const", -128); set_acts(2'b00, "max");
        run_check("int8_max_x_min", 2'b00, 1'b1, 12);

        set_weights("const", -128); set_acts(2'b01, "min");
        run_check("int4_min_x_min", 2'b01, 1'b1, 8);

        set_weights("const", -128); set_acts(2'b10, "min");
        run_check("int2_min_x_min", 2'b10, 1'b1, 6);

        // ---------------- directed: saturation ----------------
        set_weights("const", 127); set_acts(2'b00, "max");
        run_check("saturate_pos_shift0", 2'b00, 1'b1, 0);
        set_weights("const", 127); set_acts(2'b00, "min");
        run_check("saturate_neg_shift0", 2'b00, 1'b1, 0);

        // ---------------- precision 11 behaves as INT8 ----------------
        set_weights("rand"); set_acts(2'b00, "rand");
        run_check("prec_11_as_int8", 2'b11, 1'b1, 10);

        // ---------------- weights kept, back-to-back vectors ----------------
        set_weights("rand");
        set_acts(2'b00, "rand"); run_check("load_then_reuse", 2'b00, 1'b1, 10);
        repeat (5) begin
            set_acts(2'b00, "rand"); run_check("reuse_weights_int8", 2'b00, 1'b0, 10);
        end
        set_acts(2'b01, "rand"); run_check("reuse_weights_int4", 2'b01, 1'b0, 7);
        set_acts(2'b10, "rand"); run_check("reuse_weights_int2", 2'b10, 1'b0, 5);

        // ---------------- random regression ----------------
        repeat (10) begin
            set_weights("rand"); set_acts(2'b00, "rand");
            run_check("random_int8", 2'b00, 1'b1, 8 + $urandom_range(5));
        end
        repeat (10) begin
            set_acts(2'b01, "rand");
            run_check("random_int4", 2'b01, 1'b0, 5 + $urandom_range(4));
        end
        repeat (10) begin
            set_acts(2'b10, "rand");
            run_check("random_int2", 2'b10, 1'b0, 3 + $urandom_range(4));
        end

        // ---------------- summary ----------------
        repeat (3) @(negedge clk);
        $display("=====================================================================");
        $display(" SUMMARY: %0d tests, %0d passed, %0d failed, %0d total errors",
                 test_num, tests_passed, tests_failed, err_count);
        if (err_count == 0)
            $display(" *** TEST PASSED ***");
        else
            $display(" *** TEST FAILED ***");
        $display("=====================================================================");
        $stop;   // ModelSim: stops and keeps the waveform open
    end

endmodule
