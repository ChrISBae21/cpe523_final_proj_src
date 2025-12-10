import fft_consts::*;

module tb_twiddle_rom;
    logic clk;
    logic [N_LOG2-1-1:0] addr;
    complex_t data_out;

    twiddle_rom dut (
        .clk(clk),
        .addr(addr),
        .data_out(data_out)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    logic [DW_COMPLEX-1:0] expected_rom [0:(N/2)-1];
    initial $readmemh("twiddle_rom.mem", expected_rom);

    logic [DW-1:0] expected_real;
    logic [DW-1:0] expected_imag;
    
    initial begin
        for (int i = 0; i < N/2; i++) begin
            addr = i;
            @(posedge clk);
            #1;
            expected_real = expected_rom[i][DW-1:0];
            expected_imag = expected_rom[i][DW_COMPLEX-1:DW];
            assert (data_out.r === expected_real) else begin
                $error("Mismatch at addr %0h: expected real %0h, got %0h", i, expected_real, data_out.r);
            end
            assert (data_out.i === expected_imag) else begin
                $error("Mismatch at addr %0h: expected imag %0h, got %0h", i, expected_imag, data_out.i);
        end
        $display("Twiddle tests passed!");
        end
    end



endmodule