`timescale 1ns / 1ps

module complex_add(
    input  logic clk,
    input  logic rst,
    input  logic [31:0] A,
    input  logic [31:0] B,
    input  logic sub,
    output logic [31:0] Y
);

// split inputs and output into signed real/imaginary parts
logic signed [15:0] A_re, A_im, B_re, B_im;

assign A_re = A[31:16];
assign A_im = A[15:0];
assign B_re = B[31:16];
assign B_im = B[15:0];


logic signed [15:0] Y_re, Y_im;

always_comb begin
    if(!sub) begin
        Y_re = A_re + B_re;
        Y_im = A_im + B_im;
    end else begin
        Y_re = A_re - B_re;
        Y_im = A_im - B_im;
    end
end

// one clock cycle to add/subtract
always_ff @(posedge clk) begin
    if (!rst) begin
        Y <= '0;
    end else begin
        Y <= {Y_re, Y_im};
    end
end


endmodule