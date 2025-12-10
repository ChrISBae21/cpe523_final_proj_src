`timescale 1ns/1ps

import fft_consts::*;

module tb_bfu;

    // ----------------------------------------------------------------
    // Clock + reset
    // ----------------------------------------------------------------
    logic clk;
    logic rst;

    initial begin
        clk = 0;
        forever #5 clk = ~clk;   // 100 MHz clock
    end

    initial begin
        rst = 1;
        #20;                     // hold reset for a bit
        rst = 0;
    end

    // ----------------------------------------------------------------
    // DUT I/O
    // ----------------------------------------------------------------
    complex_t A_in, B_in, W_in;
    complex_t A_out, B_out;

    // Instantiate the BFU
    bfu dut (
        .clk   (clk),
        .rst   (rst),
        .A_in  (A_in),
        .B_in  (B_in),
        .W_in  (W_in),
        .A_out (A_out),
        .B_out (B_out)
    );

    // ----------------------------------------------------------------
    // Helper: Q1.15 constants (DW=16, FRAC=15)
    // We'll test with 0.25 + j0
    // ----------------------------------------------------------------

    // Convert real number in [−1,1) to Q1.15 (for TB only)
    function automatic complex_t to_q15 (real x);
        int tmp;
    begin
        tmp = $rtoi(x * (1 << FRAC_BITS));
        $display("[TB] to_q15: x=%f -> tmp=%0h", x, tmp[DW-1:0]);
        to_q15 = complex_t'(tmp[DW-1:0]);
    end
    endfunction
    
    real Aout_r_real, Aout_i_real, Bout_r_real, Bout_i_real;

    // ----------------------------------------------------------------
    // Test sequence
    // ----------------------------------------------------------------
    initial begin
        // Init inputs
        A_in = '{r:'0, i:'0};
        B_in = '{r:'0, i:'0};
        W_in = '{r:'0, i:'0};

        // Wait for reset deassert
        @(negedge rst);
        @(posedge clk);

        $display("[TB] Starting BFU test...");

        // Set A = 0.25 + j0, B = 0.25 + j0, W = 0.25 + j0
        // In Q1.15, ~0.25 ≈ 2^13 = 8192
        A_in.r = to_q15(0.25);
        A_in.i = to_q15(0.0);

        B_in.r = to_q15(0.25);
        B_in.i = to_q15(0.0);

        W_in.r = to_q15(0.25);
        W_in.i = to_q15(0.0);

        $display("[TB] Applied inputs at time %0t:", $time);
        $display("     A = (%0d, %0d)", A_in.r, A_in.i);
        $display("     B = (%0d, %0d)", B_in.r, B_in.i);
        $display("     W = (%0d, %0d)", W_in.r, W_in.i);

        // Hold inputs steady for a few cycles
        repeat (5) @(posedge clk);

        // After 3 cycles of pipeline latency (plus a bit of slack),
        // A_out, B_out should reflect the result:
        //   T   = B*W = 0.25 * 0.25 = 0.0625
        //   A'  = A + T = 0.3125
        //   B'  = A - T = 0.1875

        $display("[TB] At time %0t, BFU outputs:", $time);
        $display("     A_out = (%0d, %0d)", A_out.r, A_out.i);
        $display("     B_out = (%0d, %0d)", B_out.r, B_out.i);

        // You can also convert back to real for sanity:
        Aout_r_real = real'(A_out.r) / (1 << FRAC_BITS);
        Aout_i_real = real'(A_out.i) / (1 << FRAC_BITS);
        Bout_r_real = real'(B_out.r) / (1 << FRAC_BITS);
        Bout_i_real = real'(B_out.i) / (1 << FRAC_BITS);

        $display("     A_out (real) ≈ (%f, %f)", Aout_r_real, Aout_i_real);
        $display("     B_out (real) ≈ (%f, %f)", Bout_r_real, Bout_i_real);

        // Done
        #50;
        $display("[TB] BFU test complete.");
        $finish;
    end

endmodule
