package fft_consts;
    parameter N_LOG2 = 10;          // log2(1024)
    parameter N      = 1 << N_LOG2;
    parameter DW     = 16;           // bits per real/imag
    
    typedef struct packed {
        logic [DW-1:0] r;
        logic [DW-1:0] i;
    } complex_t;
    
//    parameter COMPLEX_ZERO = '{r: '0, i: '0};
    parameter DW_COMPLEX = $bits(complex_t);
endpackage