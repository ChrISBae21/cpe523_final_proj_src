import fft_consts::*;

module twiddle_rom (
    input logic clk,
    input logic [N_LOG2-1-1:0] addr, // address for N/2 entries
    output complex_t data_out
    );

    logic [DW_COMPLEX-1:0] rom_real [0:(N/2)-1];

    initial begin
        $readmemh("twiddle_rom.mem", rom_real);
    end

    always_ff @(posedge clk) begin
        data_out.r <= rom_real[addr][DW_COMPLEX-1:DW];
        data_out.i <= rom_real[addr][DW-1:0];
    end 

endmodule