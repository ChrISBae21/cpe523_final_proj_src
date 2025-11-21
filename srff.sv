`timescale 1ns / 1ps

module srff(
    input logic clk,
    input logic rst,
    input logic P,
    input logic S,
    input logic R,
    output logic Q,
    output logic Q_b
);

assign Q_b = ~Q;

always_ff @(posedge clk) begin
    if(!rst) begin
        Q <= 1'b0;
    end else if(!P) begin
        Q <= 1'b1;
    end else begin
        case ({S, R})
            2'b00:   Q <= Q;
            2'b01:   Q <= 1'b0;
            2'b10:   Q <= 1'b1;
            2'b11:   Q <= 1'bx;
            default: Q <= Q;
        endcase
    end
end
endmodule
