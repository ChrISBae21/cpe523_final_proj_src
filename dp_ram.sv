import fft_consts::*;

module ram_dp #(
    parameter INIT_FILE = 0,
    parameter MEM_INIT_FILE = ""
    ) (
    dp_ram_if.port_a a,
    dp_ram_if.port_b b
);

    if (INIT_FILE) begin
        initial begin
            $readmemh(MEM_INIT_FILE, mem);
        end
    end

    logic [DW_COMPLEX-1:0] mem [0:N-1];

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
