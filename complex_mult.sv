`timescale 1ns / 1ps

module complex_mult(
    input  logic clk,
    input  logic rst,
    input  logic [31:0] A,
    input  logic [31:0] B,
    output logic [63:0] Y
);


// Complex multiplication 
// ((A_r * B_r) - (A_i * B_i) + j((A_r * B_i) + (A_i * B_r))

// split inputs and output into signed real/imaginary parts
logic signed [15:0] A_re, A_im, B_re, B_im;

assign A_re = A[31:16];
assign A_im = A[15:0];
assign B_re = B[31:16];
assign B_im = B[15:0];


// multiplying doubles the bit width
logic signed [31:0] result_real, result_imag;

logic [63:0] Y_next;
logic signed [63:0] Y_reg[0:2];


always_comb begin
    result_real = (A_re * B_re) - (A_im * B_im);
    result_imag = (A_re * B_im) + (A_im * B_re);
    Y_next = {result_real, result_imag};
end

always_ff @(posedge clk) begin
    if(!rst) begin
        Y_reg[0] <= '0;
        Y_reg[1] <= '0;
        Y_reg[2] <= '0;
    end
    else begin 

        Y_reg[0] <= Y_next;
        Y_reg[1] <= Y_reg[0];
        Y_reg[2] <= Y_reg[1];
        Y <= Y_reg[2];
    end
end
endmodule



