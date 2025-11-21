`timescale 1ns/1ps

module ncounter #(
    parameter WIDTH = 4
)(
    input  logic              clk,
    input  logic              rst,
    output logic [WIDTH-1:0]  out,
    output logic              cout
);

logic [WIDTH:0] count;

always_ff @(posedge clk) begin
    if (!rst) begin
        {cout, out} <= '0;
    end else begin
        {cout, out} <= out + 1'b1;
    end
end
endmodule
