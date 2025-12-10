import fft_consts::*;

module fft1024_core (
    input  logic clk,
    input  logic rst_n,
    input  logic start,
    output logic done
    );

    // AGU
    agu_if agu_bus(clk, rst_n);

    // Drive start into interface
    always_ff @(posedge clk) begin
        if (!rst_n) agu_bus.start <= 1'b0;
        else        agu_bus.start <= start;
    end

    // Instantiate AGU in CU_FSM style
    address_gen_unit fft_agu (
        .ctrl(agu_bus)
    );

    assign done = agu_bus.done;

    complex_t A_in, B_in, W_in;
    complex_t A_out, B_out;

    // Twiddle ROM
    twiddle_rom tw_rom (
        .clk(clk),
        .addr(agu_bus.twiddle_idx),
        .data_out(W_in)
    );

    // BFU stages
    bfu bfu_unit(
        .clk(clk),
        .rst_n(rst_n),
        .A_in(),
        .B_in(),
        .W_in(W_in),
        .A_out(A_out),
        .B_out(B_out)
    );

    dp_ram_if ram_if_a(clk);
    dp_ram_if ram_if_b(clk);

    // RAM A
    ram_dp #(
        .INIT_FILE(1),
        .MEM_INIT_FILE("sine_time.mem")
    ) ram_a (
        .a(ram_if_a.port_a), // port A
        .b(ram_if_a.port_b)  // port B
    );

    // RAM B
    ram_dp ram_b (
        .a(ram_if_b.port_a), // port A
        .b(ram_if_b.port_b)  // port B
    );

    // -------------------------------
    // Read side: from RAMs into BFU
    // -------------------------------
    always_comb begin
        // RAM A
        ram_if_a.ena   = 1'b0;
        ram_if_a.wea   = 1'b0;
        ram_if_a.addra = '0;
        ram_if_a.dina  = '0;

        ram_if_a.enb   = 1'b0;
        ram_if_a.web   = 1'b0;
        ram_if_a.addrb = '0;
        ram_if_a.dinb  = '0;

        // RAM B
        ram_if_b.ena   = 1'b0;
        ram_if_b.wea   = 1'b0;
        ram_if_b.addra = '0;
        ram_if_b.dina  = '0;

        ram_if_b.enb   = 1'b0;
        ram_if_b.web   = 1'b0;
        ram_if_b.addrb = '0;
        ram_if_b.dinb  = '0;

        // Default BFU inputs
        A_in = '{r:'0, i:'0};
        B_in = '{r:'0, i:'0};

        if (agu_bus.in_valid) begin
            if (agu_bus.bank_sel == 1'b0) begin
                // READ from RAM A, WRITE to RAM B
                ram_if_a.ena   = 1'b1;
                ram_if_a.wea   = 1'b0;
                ram_if_a.addra = agu_bus.rd_addrA;

                ram_if_a.enb   = 1'b1;
                ram_if_a.web   = 1'b0;
                ram_if_a.addrb = agu_bus.rd_addrB;

                // BFU inputs from RAM A
                A_in = complex_t'(ram_if_a.douta);
                B_in = complex_t'(ram_if_a.doutb);
            end else begin
                // READ from RAM B, WRITE to RAM A
                ram_if_b.ena   = 1'b1;
                ram_if_b.wea   = 1'b0;
                ram_if_b.addra = agu_bus.rd_addrA;

                ram_if_b.enb   = 1'b1;
                ram_if_b.web   = 1'b0;
                ram_if_b.addrb = agu_bus.rd_addrB;

                // BFU inputs from RAM B
                A_in = complex_t'(ram_if_b.douta);
                B_in = complex_t'(ram_if_b.doutb);
            end
        end
    end

    // -------------------------------
    // Write side: BFU outputs back into RAMs
    // -------------------------------
    typedef struct packed {
        logic [N_LOG2-1:0] addrA;
        logic [N_LOG2-1:0] addrB;
        logic                bank_sel;
        logic                valid;
    } write_pipe_t;

    write_pipe_t pipe[0:BFU_LAT-1];

    integer i;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            for (i = 0; i < BFU_LAT; i++) begin
                pipe[i].addrA    <= '0;
                pipe[i].addrB    <= '0;
                pipe[i].bank_sel <= 1'b0;
                pipe[i].valid    <= 1'b0;
            end
        end else begin
            // shift pipeline down
            for (i = BFU_LAT-1; i > 0; i--) begin
                pipe[i] <= pipe[i-1];
            end

            // load stage 0 with current AGU info when input valid
            if (agu_bus.in_valid) begin
                pipe[0].addrA    <= agu_bus.rd_addrA;
                pipe[0].addrB    <= agu_bus.rd_addrB;
                pipe[0].bank_sel <= agu_bus.bank_sel;
                pipe[0].valid    <= 1'b1;
            end else begin
                pipe[0].addrA    <= '0;
                pipe[0].addrB    <= '0;
                pipe[0].bank_sel <= agu_bus.bank_sel;
                pipe[0].valid    <= 1'b0;
            end
        end
    end

    // Apply writes in a separate always_comb,
    // based on the last stage of the pipeline and BFU outputs.
    always_comb begin
        // Keep previous read-side enables from earlier always_comb;
        // here we only OR in the write enables.

        // Default: no extra writes
        // (We don't clear RAM enables here; that’s already done above.)

        if (pipe[BFU_LAT-1].valid) begin
            if (pipe[BFU_LAT-1].bank_sel == 1'b0) begin
                // Stage was reading from A, so now we WRITE to B
                // Use both ports: A_out → addrA, B_out → addrB
                ram_if_b.ena   = 1'b1;
                ram_if_b.wea   = 1'b1;
                ram_if_b.addra = pipe[BFU_LAT-1].addrA;
                ram_if_b.dina  = logic'(A_out);

                ram_if_b.enb   = 1'b1;
                ram_if_b.web   = 1'b1;
                ram_if_b.addrb = pipe[BFU_LAT-1].addrB;
                ram_if_b.dinb  = logic'(B_out);
            end else begin
                // Stage was reading from B, so now we WRITE to A
                ram_if_a.ena   = 1'b1;
                ram_if_a.wea   = 1'b1;
                ram_if_a.addra = pipe[BFU_LAT-1].addrA;
                ram_if_a.dina  = logic'(A_out);

                ram_if_a.enb   = 1'b1;
                ram_if_a.web   = 1'b1;
                ram_if_a.addrb = pipe[BFU_LAT-1].addrB;
                ram_if_a.dinb  = logic'(B_out);
            end
        end
    end

endmodule
