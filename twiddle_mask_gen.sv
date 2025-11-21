`timescale 1ns/1ps

module twiddle_mask_gen (
    input  logic       clk,
    input  logic       rst,
    input  logic       s_in,
    output logic [3:0] dout
);

always_ff @(posedge clk) begin
    if (!rst) begin
        dout <= 4'b0000;
    end else begin
        dout <= (s_in << 3) | (dout >> 1);
    end
end

endmodule
