module ncount_mod #(
    parameter WIDTH = 3,
    parameter MOD = 5
)(
    input  logic clk,
    input  logic clr,
    output logic [WIDTH-1:0] out,
    output logic cout
);

always_ff @(posedge clk) begin
    if (clr) begin
        out  <= '0;
        cout <= 1'b0;
    end else begin
        if (out == MOD-1) begin
            out  <= '0;
            cout <= 1'b1;
        end else begin
            out  <= out + 1;
            cout <= 1'b0;
        end
    end
end

endmodule
