`timescale 1ns / 1ps

module dff(
    input logic clk,
    input logic rst,   
    input logic P,
    input logic D,
    output logic Q
);

always_ff @(posedge clk) begin
    if(!rst) begin
        Q <= '0;    
    end else if(!P) begin
        Q <= '1;
    end else begin
        Q <= D;
    end
end
endmodule
