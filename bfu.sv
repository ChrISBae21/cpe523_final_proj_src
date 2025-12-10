`timescale 1ns / 1ps
import fft_consts::*;

module bfu (
    input  logic    clk,
    input  logic    rst_n,

    input  logic    en,       // advance pipeline when 1

    input  complex_t A_in,
    input  complex_t B_in,
    input  complex_t W_in,

    output complex_t A_out,
    output complex_t B_out
);

    // ============================================================
    // Pipeline registers
    // ============================================================

    // Stage 1: registered inputs
    complex_t A_s1, B_s1, W_s1;

    // Stage 2: wide product + delayed A
    complex_t A_s2;
    logic signed [2*FP_BITS-1:0] Tr_wide_s2, Ti_wide_s2;

    // Stage 3: truncated T and delayed A
    complex_t A_s3, T_s3, T_s3_tmp;

    // Stage 4: final outputs
    complex_t A_reg_out, B_reg_out;

    assign A_out = A_reg_out;
    assign B_out = B_reg_out;

    // ============================================================
    // Tasks (same as before)
    // ============================================================
    task automatic complex_mul_raw (
        input  complex_t                        x,
        input  complex_t                        y,
        output logic signed [2*FP_BITS-1:0]     pr,
        output logic signed [2*FP_BITS-1:0]     pi
    );
        logic signed [FP_BITS-1:0]     ar, ai, br, bi;
        logic signed [2*FP_BITS-1:0]  ar_br, ai_bi, ar_bi, ai_br;
    begin
        ar = x.r;
        ai = x.i;
        br = y.r;
        bi = y.i;

        ar_br = ar * br;
        ai_bi = ai * bi;
        ar_bi = ar * bi;
        ai_br = ai * br;

        pr = ar_br - ai_bi;
        pi = ar_bi + ai_br;
    end
    endtask

    function automatic complex_t fxp_truncate_f (
        input logic signed [2*FP_BITS-1:0] in_r,
        input logic signed [2*FP_BITS-1:0] in_i
    );
        complex_t res;
        logic signed [FP_BITS-1:0] tmp_r, tmp_i;
    begin
        tmp_r = in_r >>> FRAC_BITS;
        tmp_i = in_i >>> FRAC_BITS;

        res.r = tmp_r;
        res.i = tmp_i;

        return res;
    end
endfunction

    task automatic complex_add (
        input  complex_t a,
        input  complex_t b,
        output complex_t c
    );
    begin
        c.r = a.r + b.r;
        c.i = a.i + b.i;
    end
    endtask

    task automatic complex_sub (
        input  complex_t a,
        input  complex_t b,
        output complex_t c
    );
    begin
        c.r = a.r - b.r;
        c.i = a.i - b.i;
    end
    endtask

    // ============================================================
    // Pipeline stages with en
    // ============================================================

    // Stage 1: register raw inputs
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            A_s1 <= '0;
            B_s1 <= '0;
            W_s1 <= '0;
        end else if (en) begin
            A_s1 <= A_in;
            B_s1 <= B_in;
            W_s1 <= W_in;
        end
    end

    // Stage 2: wide complex multiply T = B_s1 * W_s1, delay A
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            Tr_wide_s2 <= '0;
            Ti_wide_s2 <= '0;
            A_s2       <= '0;
        end else if (en) begin
            complex_mul_raw(B_s1, W_s1, Tr_wide_s2, Ti_wide_s2);
            // A_s2 <= A_s1;
        end
    end

    // Stage 3: truncate T and delay A again
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            T_s3 <= '0;
            A_s3 <= '0;
        end else if (en) begin
            T_s3 <= fxp_truncate_f(Tr_wide_s2, Ti_wide_s2);
            A_s3 <= A_s1;
        end
    end

    // Stage 4: butterfly (A+-T) and register outputs
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            A_reg_out <= '0;
            B_reg_out <= '0;
        end else if (en) begin
            complex_t sum, diff;
            complex_add(A_s3, T_s3, sum);   // A' = A + T
            complex_sub(A_s3, T_s3, diff);  // B' = A - T
            A_reg_out <= sum;
            B_reg_out <= diff;
        end
    end

endmodule
