`timescale 1ns/1ps

import fft_consts::*;

module tb_ram_dp;
    logic clk;

    initial begin
        clk = 0;
    end

    always #5 clk = ~clk;

    dp_ram_if ram(clk);

    ram_dp dut (
         .a(ram),  // use interface as port_a
         .b(ram)   // use interface as port_b (same instance, both ports)
    );

    logic [DW-1:0] read_a_data, read_b_data;
    logic [DW-1:0] expected_data [0:N-1];


    initial begin
        // Reset RAM interface
        ram.reset();

        // Write some data to Port A
        for (int i = 0; i < 16; i++) begin
            ram.write_a(i, i * 10); 
            expected_data[i] = i * 10;
        end

        // Read back data from Port B and display
        for (int i = 0; i < 16; i++) begin
            ram.read_b(i, read_b_data);
            assert(read_b_data === expected_data[i]) 
            else $error("Port B Read Mismatch at addr %0d: got %0d, expected %0d", i, read_b_data, expected_data[i]);
        end

        // Write some data to Port B
        for (int i = 16; i < 32; i++) begin
            ram.write_b(i, i * 20); 
            expected_data[i] = i * 20;
        end

        // Read back data from Port A and display
        for (int i = 16; i < 32; i++) begin
            ram.read_a(i, read_a_data);
            assert(read_a_data === expected_data[i])
            else $error("Port A Read Mismatch at addr %0d: got %0d, expected %0d", i, read_a_data, expected_data[i]);
        end

        $display("DP RAM tests passed.");
        $finish;
    end

endmodule
