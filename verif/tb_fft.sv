module tb_fft ();

    logic clk;
    logic rst_n;

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100MHz clock
    end

    logic start;
    logic done;

    fft1024_core dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .done(done)
    );

    initial begin
        rst_n = 1;
        start = 0;
        @(posedge clk);
        rst_n = 0;
        @(posedge clk);
        rst_n = 1;
        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;

        wait (done);
        
        // dump results or check outputs here
        @(posedge clk);
        $display("[TB] Dumping RAM B contents to fft_output.mem");
        $writememh("fft_output.mem", dut.ram0.mem);

        $finish;
    end



endmodule