import fft_consts::*;

module ram_dp #(
    parameter int    INIT_FILE     = 0,
    parameter string MEM_INIT_FILE = ""
) (
    dp_ram_if.port_a a,
    dp_ram_if.port_b b
);

    // Memory: one complex word per address
    logic [DW_COMPLEX-1:0] mem [0:N-1];

    // Optional initialization
    generate
        if (INIT_FILE) begin 
            initial begin
                $display("[ram_dp] Initializing from %s", MEM_INIT_FILE);
                $readmemh(MEM_INIT_FILE, mem);
            end
        end
    endgenerate

    // Port A operations
    always_ff @(posedge a.clk) begin
        if (a.ena) begin
            if (a.wea) begin
                mem[a.addra] <= a.dina;   // write full complex word
            end
            a.douta <= mem[a.addra];      // read full complex word
        end
    end

    // Port B operations
    always_ff @(posedge b.clk) begin
        if (b.enb) begin
            if (b.web) begin
                mem[b.addrb] <= b.dinb;   // write full complex word
            end
            b.doutb <= mem[b.addrb];      // read full complex word
        end
    end

endmodule