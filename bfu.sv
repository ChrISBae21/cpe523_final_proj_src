`timescale 1ns / 1ps

import fft_consts::*;


module bfu (
    input logic clk,
    input logic rst_n,

    input complex_t A_in,
    input complex_t B_in,
    input complex_t W_in,

    output complex_t A_out,
    output complex_t B_out
);
    // -----------------------------
    // Internal pipeline registers
    // -----------------------------

    // Stage 0 -> Stage 1: register raw inputs
    complex_t A_s1, B_s1, W_s1;

    // Stage 1 -> Stage 2: complex product B*W (wide)
    logic signed [2*DW-1:0] Tr_wide_s2, Ti_wide_s2;

    // Stage 2 -> Stage 3: truncated T plus delayed A
    complex_t T_s3;   // truncated to DW bits (Q1.15)
    complex_t A_s3;   // delayed A aligned with T

    // Final outputs registered
    complex_t A_reg_out, B_reg_out;

    assign A_out = A_reg_out;
    assign B_out = B_reg_out;

    // Complex multiply (full precision, no truncation)
    //   (ar + j ai) * (br + j bi) = (ar*br - ai*bi) + j(ar*bi + ai*br)
    task automatic complex_mul_raw (
        input  complex_t               x,
        input  complex_t               y,
        output logic signed [2*FP_BITS-1:0] pr,
        output logic signed [2*FP_BITS-1:0] pi
    );
        logic signed [FP_BITS-1:0] ar, ai, br, bi;
        logic signed [2*FP_BITS-1:0] ar_br, ai_bi, ar_bi, ai_br;
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

    // Fixed-point truncate/round from wide product to DW bits
    task automatic fxp_truncate (
        input  logic signed [2*FP_BITS-1:0] in_r,
        input  logic signed [2*FP_BITS-1:0] in_i,
        output complex_t               out
    );
    begin
        out.r = in_r >>> FRAC_BITS;
        out.i = in_i >>> FRAC_BITS;
    end
    endtask

    // Complex add: c = a + b
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

    // Complex sub: c = a - b
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

    task automatic delay_complex (
        input  complex_t in,
        output complex_t out
    );
    begin
        out = in;
    end
    endtask

    // ============================================================
    // Pipeline implementation
    // ============================================================

    // Stage 0 -> Stage 1: register inputs
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            A_s1 <= '0;
            B_s1 <= '0;
            W_s1 <= '0;
        end else begin
            delay_complex(A_in, A_s1);
            delay_complex(B_in, B_s1);
            delay_complex(W_in, W_s1);
        end
    end

    // Stage 1 -> Stage 2: compute wide complex product T = B*W
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            Tr_wide_s2 <= '0;
            Ti_wide_s2 <= '0;
        end else begin
            complex_mul_raw(B_s1, W_s1, Tr_wide_s2, Ti_wide_s2);
        end
    end

    // Stage 2 -> Stage 3: truncate T and align A
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            T_s3  <= '0;
            A_s3  <= '0;
        end else begin
            fxp_truncate(Tr_wide_s2, Ti_wide_s2, T_s3);
            delay_complex(A_s1, A_s3);  // one-cycle delay to align with T_s3
        end
    end

    // Stage 3: final butterfly add/sub and register outputs
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            A_reg_out <= '0;
            B_reg_out <= '0;
        end else begin
            complex_t sum, diff;
            complex_add(A_s3, T_s3, sum);
            complex_sub(A_s3, T_s3, diff);
            A_reg_out <= sum;   // A' = A + T
            B_reg_out <= diff;  // B' = A - T
        end
    end

endmodule
