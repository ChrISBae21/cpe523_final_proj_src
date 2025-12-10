import fft_consts::*;

module ram_dp (
    dp_ram_if.port_a a,
    dp_ram_if.port_b b
);

    logic [DW-1:0] mem [0:N-1];

    // Port A operations
    always_ff @(posedge a.clk) begin
        if (a.ena) begin
            if (a.wea) begin
                mem[a.addra] <= a.dina;
            end
            a.douta <= mem[a.addra];
        end
    end

    // Port B operations
    always_ff @(posedge b.clk) begin
        if (b.enb) begin
            if (b.web) begin
                mem[b.addrb] <= b.dinb;
            end
            b.doutb <= mem[b.addrb];
        end
    end

endmodule
