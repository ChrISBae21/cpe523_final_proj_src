package fft_consts;
    parameter N_LOG2 = 10;          // log2(1024)
    parameter N      = 1 << N_LOG2;
    parameter DW     = 16;           // bits per real/imag
    
    parameter SIGN_BITS = 1;
    parameter FRAC_BITS = 15;
    parameter FP_BITS = SIGN_BITS + FRAC_BITS;
    
    typedef struct packed {
        logic [FP_BITS-1:0] r;
        logic [FP_BITS-1:0] i;
    } complex_t;
    
//    parameter COMPLEX_ZERO = '{r: '0, i: '0};
    parameter DW_COMPLEX = $bits(complex_t);


endpackage

interface dp_ram_if (input logic clk);
        import fft_consts::*;
        
        // Port A
        logic              ena;
        logic              wea;
        logic [N_LOG2-1:0] addra;
        logic [DW-1:0]     dina;
        logic [DW-1:0]     douta;
        
        // Port B
        logic              enb;
        logic              web;
        logic [N_LOG2-1:0] addrb;
        logic [DW-1:0]     dinb;
        logic [DW-1:0]     doutb;

        modport port_a (
            input  clk,
            input  ena,
            input  wea,
            input  addra,
            input  dina,
            output douta
        );

        modport port_b (
            input  clk,
            input  enb,
            input  web,
            input  addrb,
            input  dinb,
            output doutb
        );

        task automatic reset();
            ena   = 0;
            wea   = 0;
            addra = '0;
            dina  = '0;
            douta = '0;

            enb   = 0;
            web   = 0;
            addrb = '0;
            dinb  = '0;
            doutb = '0;
            @(posedge clk);
        endtask

        task automatic write_a(input logic [N_LOG2-1:0] addr, input logic [DW-1:0] data);
            ena   = 1;
            wea   = 1;
            addra = addr;
            dina  = data;
            @(posedge clk);
            wea   = 0; // disable write
        endtask

        task automatic read_a(input logic [N_LOG2-1:0] addr, output logic [DW-1:0] data);
            ena   = 1;
            addra = addr;
            @(posedge clk);
            data  = douta;
        endtask 

        task automatic write_b(input logic [N_LOG2-1:0] addr, input logic [DW-1:0] data);
            enb   = 1;
            web   = 1;
            addrb = addr;
            dinb  = data;
            @(posedge clk);
            web   = 0; // disable write
        endtask

        task automatic read_b(input logic [N_LOG2-1:0] addr, output logic [DW-1:0] data);
            enb   = 1;
            addrb = addr;
            @(posedge clk);
            data  = doutb;
        endtask

    endinterface