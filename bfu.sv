`timescale 1ns / 1ps

module bfu(
    input  logic        clk,
    input  logic        rst,
    input  logic [31:0] A,
    input  logic [31:0] B,
    input  logic [31:0] w,   // twiddle factor
    output logic [31:0] A_b, // A'
    output logic [31:0] B_b  // B'
);

// ------------------------------------------------------------
// 4-cycle delay pipeline for A
// ------------------------------------------------------------
logic [31:0] A_delay [0:3];
// Output of the delay pipe
logic [31:0] A_delayed;

always_ff @(posedge clk) begin
    if (rst) begin
        A_delay[0] <= '0;
        A_delay[1] <= '0;
        A_delay[2] <= '0;
//        A_delay[3] <= '0;
    end else begin
        A_delay[0] <= A;
        A_delay[1] <= A_delay[0];
        A_delay[2] <= A_delay[1];
//        A_delay[3] <= A_delay[2];
        A_delayed <= A_delay[2];
    end
end


//assign A_delayed = A_delay[3];

// ------------------------------------------------------------
// Complex multiply: B * w (already 4-cycle latency)
// ------------------------------------------------------------
logic [63:0] mult_out;
complex_mult cmult (
    .clk(clk),
    .rst(rst),
    .A(B),
    .B(w),
    .Y(mult_out)      // 64-bit result
);

// Truncate multiplier output to 32 bits (Q15 format)
logic [31:0] BW_trunc;
assign BW_trunc = {mult_out[63:48], mult_out[31:16]};

// ------------------------------------------------------------
// Complex adder: upper (A + BW)
// ------------------------------------------------------------
complex_add cadd_top (
    .clk(clk),
    .rst(rst),
    .A(A_delayed),
    .B(BW_trunc),
    .sub(1'b0),
    .Y(A_b)
);

// ------------------------------------------------------------
// Complex adder: lower (A - BW)
// ------------------------------------------------------------
complex_add cadd_bottom (
    .clk(clk),
    .rst(rst),
    .A(A_delayed),
    .B(BW_trunc),
    .sub(1'b1),
    .Y(B_b)
);

endmodule
