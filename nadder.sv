`timescale 1ns / 1ps

module nadder #(
    parameter WIDTH = 5
)(
    input  logic clk,
    input  logic rst,
    input  logic [WIDTH-1:0] A,
    input  logic [WIDTH-1:0] B,
    output logic [WIDTH-1:0] Y
);

always_ff @(posedge clk) begin
    if(!rst) Y <= '0;
    else Y <= A + B;
end
endmodule
