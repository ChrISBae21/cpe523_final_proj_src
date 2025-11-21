`timescale 1ns / 1ps

module npipeline #(
    parameter WIDTH = 32,   // Data width to delay
    parameter DEPTH = 4     // Number of stages
)(
    input  logic clk,
    input  logic rst,
    input  logic [WIDTH-1:0] in,
    output logic [WIDTH-1:0] out
);

logic [WIDTH-1:0] stage [0:DEPTH-1];

always_ff @(posedge clk) begin
    if (!rst) begin
        for(int i = 0; i < DEPTH; i++)
            stage[i] <= '0;
    end else begin
        stage[0] <= in;
        for(int i = 1; i < DEPTH; i++)
            stage[i] <= stage[i-1];
    end
end

assign out = stage[DEPTH-1];

endmodule
