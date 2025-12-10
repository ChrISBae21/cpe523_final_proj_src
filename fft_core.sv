// fft1024_core.sv
import fft_consts::*;

module fft1024_core (
    input  logic clk,
    input  logic rst_n,
    input  logic start,
    output logic done
);

    // ------------------------------------------------------------
    // AGU + control
    // ------------------------------------------------------------
    agu_if agu_bus (clk, rst_n);

    // Drive start into interface (one-shot style from top)
    always_ff @(posedge clk) begin
        if (!rst_n)
            agu_bus.start <= 1'b0;
        else
            agu_bus.start <= start;
    end

    // Address Generation Unit (with FLUSH state)
    address_gen_unit u_agu (
        .ctrl(agu_bus)
    );

    assign done = agu_bus.done;

    // Aliases for readability
    wire              agu_in_valid = agu_bus.in_valid;
    wire [N_LOG2-1:0] agu_rdA      = agu_bus.rd_addrA;
    wire [N_LOG2-1:0] agu_rdB      = agu_bus.rd_addrB;
    wire              agu_bank_sel = agu_bus.bank_sel;     // 0: read ram0, 1: read ram1
    wire [N_LOG2-2:0] agu_tw_idx   = agu_bus.twiddle_idx;

    // ------------------------------------------------------------
    // BFU + Twiddle ROM
    // ------------------------------------------------------------
    complex_t A_in, B_in, W_in;
    complex_t A_out, B_out;

    // 1-cycle delay to align synchronous RAM + ROM outputs with BFU enable
    logic              v_d1;
    logic [N_LOG2-1:0] rdA_d1, rdB_d1;
    logic              bank_sel_d1;
    logic [N_LOG2-2:0] twiddle_idx_d1;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            v_d1           <= 1'b0;
            rdA_d1         <= '0;
            rdB_d1         <= '0;
            bank_sel_d1    <= 1'b0;
            twiddle_idx_d1 <= '0;
        end else begin
            v_d1           <= agu_in_valid;
            rdA_d1         <= agu_rdA;
            rdB_d1         <= agu_rdB;
            bank_sel_d1    <= agu_bank_sel;
            twiddle_idx_d1 <= agu_tw_idx;
        end
    end

    // Twiddle ROM (synchronous) – address is already delayed
    twiddle_rom tw_rom (
        .clk     (clk),
        .addr    (agu_tw_idx),
        .data_out(W_in)
    );

    // BFU enable: advance pipeline when A_in/B_in/W_in valid
    logic bfu_en;
    assign bfu_en = v_d1;

    bfu u_bfu (
        .clk   (clk),
        .rst_n (rst_n),
        .en    (bfu_en),
        .A_in  (A_in),
        .B_in  (B_in),
        .W_in  (W_in),
        .A_out (A_out),
        .B_out (B_out)
    );

    // ------------------------------------------------------------
    // Dual-port RAMs: ram0 and ram1 with dp_ram_if
    // ------------------------------------------------------------
    dp_ram_if ram0_if (clk);
    dp_ram_if ram1_if (clk);

    // ram0 initialised with time-domain data
    ram_dp #(
        .INIT_FILE    (1),
        .MEM_INIT_FILE("sine_time.mem")
    ) ram0 (
        .a(ram0_if.port_a),
        .b(ram0_if.port_b)
    );

    // ram1 empty at start
    ram_dp ram1 (
        .a(ram1_if.port_a),
        .b(ram1_if.port_b)
    );

    // ------------------------------------------------------------
    // Write-back pipeline: track addresses & read bank per butterfly
    // ------------------------------------------------------------
    typedef struct packed {
        logic [N_LOG2-1:0] addrA;
        logic [N_LOG2-1:0] addrB;
        logic              bank_sel;  // bank that was READ for this butterfly
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
            // shift pipeline
            for (i = BFU_LAT-1; i > 0; i--) begin
                pipe[i] <= pipe[i-1];
            end

            // load pipe[0] when a new butterfly is issued (after 1-cycle delay)
            if (v_d1) begin
                pipe[0].addrA    <= rdA_d1;
                pipe[0].addrB    <= rdB_d1;
                pipe[0].bank_sel <= bank_sel_d1;  // 0: read ram0, 1: read ram1
                pipe[0].valid    <= 1'b1;
            end else begin
                pipe[0].addrA    <= '0;
                pipe[0].addrB    <= '0;
                pipe[0].bank_sel <= bank_sel_d1;
                pipe[0].valid    <= 1'b0;
            end
        end
    end

    logic read_from_ram0, read_from_ram1;
    logic write_to_ram0, write_to_ram1;

    write_pipe_t last;

    // ------------------------------------------------------------
    // Combined READ/WRITE control + BFU inputs (ping-pong)
    // ------------------------------------------------------------
    always_comb begin
        // ---- defaults ----
        // ram0
        ram0_if.ena   = 1'b0;
        ram0_if.wea   = 1'b0;
        ram0_if.addra = '0;
        ram0_if.dina  = '0;

        ram0_if.enb   = 1'b0;
        ram0_if.web   = 1'b0;
        ram0_if.addrb = '0;
        ram0_if.dinb  = '0;

        // ram1
        ram1_if.ena   = 1'b0;
        ram1_if.wea   = 1'b0;
        ram1_if.addra = '0;
        ram1_if.dina  = '0;

        ram1_if.enb   = 1'b0;
        ram1_if.web   = 1'b0;
        ram1_if.addrb = '0;
        ram1_if.dinb  = '0;

        // BFU inputs
        A_in = '{r:'0, i:'0};
        B_in = '{r:'0, i:'0};

        // ---- read-issue from AGU (current stage) ----
        read_from_ram0 = agu_in_valid && (agu_bank_sel == 1'b0);
        read_from_ram1 = agu_in_valid && (agu_bank_sel == 1'b1);

        // ---- write-back (BFU latency slots, previous butterflies) ----
        last = pipe[BFU_LAT-1];

        // If we read from ram0 for this butterfly, we must write results to ram1
        // => last.bank_sel==0  -> dest = ram1
        //    last.bank_sel==1  -> dest = ram0
        write_to_ram1 = last.valid && (last.bank_sel == 1'b0);
        write_to_ram0 = last.valid && (last.bank_sel == 1'b1);

        // ---------------- RAM0 control ----------------
        // Port A (addrA / A_out)
        ram0_if.ena = read_from_ram0 || write_to_ram0;
        ram0_if.wea = write_to_ram0;

        if (write_to_ram0)
            ram0_if.addra = last.addrA;
        else if (read_from_ram0)
            ram0_if.addra = agu_rdA;
        else
            ram0_if.addra = '0;

        if (write_to_ram0)
            ram0_if.dina = DW_COMPLEX'(A_out);
        else
            ram0_if.dina = '0;

        // Port B (addrB / B_out)
        ram0_if.enb = read_from_ram0 || write_to_ram0;
        ram0_if.web = write_to_ram0;

        if (write_to_ram0)
            ram0_if.addrb = last.addrB;
        else if (read_from_ram0)
            ram0_if.addrb = agu_rdB;
        else
            ram0_if.addrb = '0;

        if (write_to_ram0)
            ram0_if.dinb = DW_COMPLEX'(B_out);
        else
            ram0_if.dinb = '0;

        // ---------------- RAM1 control ----------------
        // Port A
        ram1_if.ena = read_from_ram1 || write_to_ram1;
        ram1_if.wea = write_to_ram1;

        if (write_to_ram1)
            ram1_if.addra = last.addrA;
        else if (read_from_ram1)
            ram1_if.addra = agu_rdA;
        else
            ram1_if.addra = '0;

        if (write_to_ram1)
            ram1_if.dina = DW_COMPLEX'(A_out);
        else
            ram1_if.dina = '0;

        // Port B
        ram1_if.enb = read_from_ram1 || write_to_ram1;
        ram1_if.web = write_to_ram1;

        if (write_to_ram1)
            ram1_if.addrb = last.addrB;
        else if (read_from_ram1)
            ram1_if.addrb = agu_rdB;
        else
            ram1_if.addrb = '0;

        if (write_to_ram1)
            ram1_if.dinb = DW_COMPLEX'(B_out);
        else
            ram1_if.dinb = '0;

        // ---------------- BFU input selection ----------------
        // Use delayed bank_sel_d1 to pick which RAM outputs feed the BFU
        if (v_d1 && (bank_sel_d1 == 1'b0)) begin
            A_in = complex_t'(ram0_if.douta);
            B_in = complex_t'(ram0_if.doutb);
        end else if (v_d1 && (bank_sel_d1 == 1'b1)) begin
            A_in = complex_t'(ram1_if.douta);
            B_in = complex_t'(ram1_if.doutb);
        end else begin
            A_in = '{r:'0, i:'0};
            B_in = '{r:'0, i:'0};
        end
    end

endmodule
