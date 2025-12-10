import fft_consts::*;

module fft1024_core (
    input  logic clk,
    input  logic rst_n,
    input  logic start,
    output logic done
);

    // -------------------------------
    // AGU
    // -------------------------------
    agu_if agu_bus(clk, rst_n);

    // Drive start into interface
    always_ff @(posedge clk) begin
        if (!rst_n)
            agu_bus.start <= 1'b0;
        else
            agu_bus.start <= start;
    end

    // Instantiate AGU
    address_gen_unit fft_agu (
        .ctrl(agu_bus)
    );

    assign done = agu_bus.done;

    // Aliases for AGU outputs (issue phase)
    wire              agu_in_valid = agu_bus.in_valid;
    wire [N_LOG2-1:0] agu_rdA      = agu_bus.rd_addrA;
    wire [N_LOG2-1:0] agu_rdB      = agu_bus.rd_addrB;
    wire              agu_bank_sel = agu_bus.bank_sel;
    wire [N_LOG2-2:0] agu_tw_idx   = agu_bus.twiddle_idx;

    // -------------------------------
    // BFU + Twiddle ROM
    // -------------------------------
    complex_t A_in, B_in, W_in;
    complex_t A_out, B_out;

    // 1-cycle delayed versions to line up with synchronous RAM
    logic              v_d1;
    logic [N_LOG2-1:0] rdA_d1, rdB_d1;
    logic              bank_sel_d1;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            v_d1        <= 1'b0;
            rdA_d1      <= '0;
            rdB_d1      <= '0;
            bank_sel_d1 <= 1'b0;
        end else begin
            v_d1        <= agu_in_valid;   // delayed valid
            rdA_d1      <= agu_rdA;        // delayed addresses
            rdB_d1      <= agu_rdB;
            bank_sel_d1 <= agu_bank_sel;   // delayed bank
        end
    end

    // Twiddle ROM: use AGU twiddle index (issue phase)
    twiddle_rom tw_rom (
        .clk     (clk),
        .addr    (agu_tw_idx),
        .data_out(W_in)   // W_in valid when BFU en = v_d1
    );

    // BFU enable: advance when RAM outputs are valid
    logic bfu_en;
    assign bfu_en = v_d1;

    bfu bfu_unit (
        .clk   (clk),
        .rst_n (rst_n),
        .en    (bfu_en),
        .A_in  (A_in),
        .B_in  (B_in),
        .W_in  (W_in),
        .A_out (A_out),
        .B_out (B_out)
    );

    // -------------------------------
    // RAMs
    // -------------------------------
    dp_ram_if ram_if_a(clk);
    dp_ram_if ram_if_b(clk);

    // RAM A
    ram_dp #(
        .INIT_FILE    (1),
        .MEM_INIT_FILE("sine_time.mem")
    ) ram_a (
        .a(ram_if_a.port_a),
        .b(ram_if_a.port_b)
    );

    // RAM B
    ram_dp ram_b (
        .a(ram_if_b.port_a),
        .b(ram_if_b.port_b)
    );

    // -------------------------------
    // Writeback pipeline
    // -------------------------------
    typedef struct packed {
        logic [N_LOG2-1:0] addrA;
        logic [N_LOG2-1:0] addrB;
        logic              bank_sel; // bank that was READ
        logic              valid;
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
            // shift
            for (i = BFU_LAT-1; i > 0; i--) begin
                pipe[i] <= pipe[i-1];
            end

            // load stage 0 when BFU is taking a new butterfly
            if (v_d1) begin
                pipe[0].addrA    <= rdA_d1;        // delayed read addresses
                pipe[0].addrB    <= rdB_d1;
                pipe[0].bank_sel <= bank_sel_d1;   // bank that was *read*
                pipe[0].valid    <= 1'b1;
            end else begin
                pipe[0].addrA    <= '0;
                pipe[0].addrB    <= '0;
                pipe[0].bank_sel <= bank_sel_d1;
                pipe[0].valid    <= 1'b0;
            end
        end
    end

    logic read_issue_A, read_issue_B;
    logic useA_for_bfu, useB_for_bfu;
    logic write_to_A, write_to_B;

    // -------------------------------
    // Read + Write Control + BFU inputs
    // -------------------------------
    always_comb begin
        // Defaults
        ram_if_a.ena   = 1'b0;
        ram_if_a.wea   = 1'b0;
        ram_if_a.addra = '0;
        ram_if_a.dina  = '0;

        ram_if_a.enb   = 1'b0;
        ram_if_a.web   = 1'b0;
        ram_if_a.addrb = '0;
        ram_if_a.dinb  = '0;

        ram_if_b.ena   = 1'b0;
        ram_if_b.wea   = 1'b0;
        ram_if_b.addra = '0;
        ram_if_b.dina  = '0;

        ram_if_b.enb   = 1'b0;
        ram_if_b.web   = 1'b0;
        ram_if_b.addrb = '0;
        ram_if_b.dinb  = '0;

        A_in = '{r:'0, i:'0};
        B_in = '{r:'0, i:'0};

        // ---------- Read ISSUE (addresses from AGU) ----------
        read_issue_A = agu_in_valid && (agu_bank_sel == 1'b0);
        read_issue_B = agu_in_valid && (agu_bank_sel == 1'b1);

        // ---------- BFU DATA select (delayed bank_sel) ----------
        useA_for_bfu = v_d1 && (bank_sel_d1 == 1'b0);
        useB_for_bfu = v_d1 && (bank_sel_d1 == 1'b1);

        // ---------- Write side (from BFU outputs) ----------
        write_to_B = pipe[BFU_LAT-1].valid && (pipe[BFU_LAT-1].bank_sel == 1'b0);
        write_to_A = pipe[BFU_LAT-1].valid && (pipe[BFU_LAT-1].bank_sel == 1'b1);

        // ---------------- RAM A control ----------------
        // Port A
        ram_if_a.ena = read_issue_A || write_to_A;
        ram_if_a.wea = write_to_A;

        if (read_issue_A)
            ram_if_a.addra = agu_rdA;
        else if (write_to_A)
            ram_if_a.addra = pipe[BFU_LAT-1].addrA;
        else
            ram_if_a.addra = '0;

        if (write_to_A)
            ram_if_a.dina = logic'(A_out);
        else
            ram_if_a.dina = '0;

        // Port B
        ram_if_a.enb = read_issue_A || write_to_A;
        ram_if_a.web = write_to_A;

        if (read_issue_A)
            ram_if_a.addrb = agu_rdB;
        else if (write_to_A)
            ram_if_a.addrb = pipe[BFU_LAT-1].addrB;
        else
            ram_if_a.addrb = '0;

        if (write_to_A)
            ram_if_a.dinb = logic'(B_out);
        else
            ram_if_a.dinb = '0;

        // ---------------- RAM B control ----------------
        // Port A
        ram_if_b.ena = read_issue_B || write_to_B;
        ram_if_b.wea = write_to_B;

        if (read_issue_B)
            ram_if_b.addra = agu_rdA;
        else if (write_to_B)
            ram_if_b.addra = pipe[BFU_LAT-1].addrA;
        else
            ram_if_b.addra = '0;

        if (write_to_B)
            ram_if_b.dina = logic'(A_out);
        else
            ram_if_b.dina = '0;

        // Port B
        ram_if_b.enb = read_issue_B || write_to_B;
        ram_if_b.web = write_to_B;

        if (read_issue_B)
            ram_if_b.addrb = agu_rdB;
        else if (write_to_B)
            ram_if_b.addrb = pipe[BFU_LAT-1].addrB;
        else
            ram_if_b.addrb = '0;

        if (write_to_B)
            ram_if_b.dinb = logic'(B_out);
        else
            ram_if_b.dinb = '0;

        // ---------------- BFU inputs ----------------
        if (useA_for_bfu) begin
            A_in = complex_t'(ram_if_a.douta);
            B_in = complex_t'(ram_if_a.doutb);
        end else if (useB_for_bfu) begin
            A_in = complex_t'(ram_if_b.douta);
            B_in = complex_t'(ram_if_b.doutb);
        end else begin
            A_in = '{r:'0, i:'0};
            B_in = '{r:'0, i:'0};
        end
    end

endmodule
