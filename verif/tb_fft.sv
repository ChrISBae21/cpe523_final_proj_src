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
        #20;
        rst_n = 0;
        #20;
        rst_n = 1;
        start = 1;
        #10;
        start = 0;

        // wait (done);
        repeat (50) @(posedge clk);
        $finish;
    end



endmodule