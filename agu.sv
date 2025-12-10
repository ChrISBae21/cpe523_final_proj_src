// address_gen_unit.sv
import fft_consts::*;

module address_gen_unit (
    agu_if.fsm ctrl
);

    localparam int N_LOG2_P = N_LOG2;
    localparam int N_P      = 1 << N_LOG2_P;

    // How many cycles to wait for BFU + RAM pipeline to flush
    localparam int FLUSH_CYCLES = BFU_LAT;
    localparam int FLUSH_W      = (FLUSH_CYCLES <= 1) ? 1 : $clog2(FLUSH_CYCLES+1);

    // FSM states
    typedef enum logic [1:0] {
        INIT,   // idle / waiting for start
        RUN,    // issuing butterflies
        FLUSH,  // pipeline draining between stages
        DONE    // finished all stages
    } state_t;

    state_t PS, NS;

    // Counters
    logic [N_LOG2_P-1:0] stage_reg;    // 0 .. N_LOG2-1
    logic [N_LOG2_P-1:0] group_cnt;    // group index in this stage
    logic [N_LOG2_P-1:0] j_cnt;        // butterfly index in this group

    // Per-stage derived values
    logic [N_LOG2_P-1:0] stride;       // 2^stage
    logic [N_LOG2_P-1:0] group_size;   // 2^(stage+1)
    logic [N_LOG2_P-1:0] num_groups;   // N / group_size
    logic [N_LOG2_P-1:0] group_base;   // base addr of current group
    logic [N_LOG2_P-1:0] tw_step;      // NEW: N / group_size
    logic [N_LOG2_P-1:0] exp;          // NEW: twiddle exponent

    logic                 last_j;
    logic                 last_group;
    logic                 last_butterfly;

    // Ping-pong bank select (toggles once per stage)
    logic bank_sel_reg;

    // Flush counter
    logic [FLUSH_W-1:0] flush_cnt;

    // ------------------------------------------------------------
    // Derived combinational signals
    // ------------------------------------------------------------
    always_comb begin
        // 2^stage
        stride     = 1 << stage_reg;
        // group size = 2 * stride
        group_size = stride << 1;
        // number of groups = N / 2^(stage+1)
        num_groups = N_P >> (stage_reg + 1);

        // current group's base address
        group_base = group_cnt << (stage_reg + 1);

        tw_step    = N_P >> (stage_reg + 1);   // N / group_size
        exp        = j_cnt * tw_step;          // twiddle exponent

        last_j         = (j_cnt     == (stride    - 1));
        last_group     = (group_cnt == (num_groups - 1));
        last_butterfly = last_j && last_group;
    end

    // ------------------------------------------------------------
    // State register
    // ------------------------------------------------------------
    always_ff @(posedge ctrl.clk) begin
        if (!ctrl.rst_n)
            PS <= INIT;
        else
            PS <= NS;
    end

    // ------------------------------------------------------------
    // Sequential counters, bank_sel, and flush counter
    // ------------------------------------------------------------
    always_ff @(posedge ctrl.clk) begin
        if (!ctrl.rst_n) begin
            stage_reg    <= '0;
            group_cnt    <= '0;
            j_cnt        <= '0;
            bank_sel_reg <= 1'b0;
            flush_cnt    <= '0;
        end else begin
            case (PS)
                INIT: begin
                    if (ctrl.start) begin
                        stage_reg    <= '0;
                        group_cnt    <= '0;
                        j_cnt        <= '0;
                        bank_sel_reg <= 1'b0;   // start reading ram0, writing ram1
                        flush_cnt    <= '0;
                    end
                end

                RUN: begin
                    // normal butterfly stepping within this stage
                    if (!last_butterfly) begin
                        if (last_j) begin
                            j_cnt     <= '0;
                            group_cnt <= group_cnt + 1;
                        end else begin
                            j_cnt     <= j_cnt + 1;
                        end
                    end

                    // When we hit the last butterfly of this stage, prepare to flush
                    if (last_butterfly) begin
                        flush_cnt <= FLUSH_CYCLES[FLUSH_W-1:0];
                    end
                end

                FLUSH: begin
                    // Count down until pipeline is empty
                    if (flush_cnt != 0)
                        flush_cnt <= flush_cnt - 1'b1;
                    else begin
                        // Flush done: either move to next stage or stay for DONE
                        if (stage_reg != (N_LOG2_P-1)) begin
                            stage_reg    <= stage_reg + 1;
                            group_cnt    <= '0;
                            j_cnt        <= '0;
                            bank_sel_reg <= ~bank_sel_reg; // swap banks
                        end
                        // For last stage we leave stage_reg as is; DONE state
                    end
                end

                DONE: begin
                    // hold stage_reg / bank_sel / counters until next start
                end

                default: ;
            endcase
        end
    end

    // ------------------------------------------------------------
    // Next-state and outputs
    // ------------------------------------------------------------
    always_comb begin
        // Default: stay in same state
        NS = PS;

        // Default outputs
        ctrl.busy        = 1'b0;
        ctrl.done        = 1'b0;
        ctrl.in_valid    = 1'b0;
        ctrl.rd_addrA    = '0;
        ctrl.rd_addrB    = '0;
        ctrl.twiddle_idx = '0;
        ctrl.stage       = stage_reg;
        ctrl.bank_sel    = bank_sel_reg;

        case (PS)
            INIT: begin
                ctrl.busy = 1'b0;
                ctrl.done = 1'b0;
                if (ctrl.start)
                    NS = RUN;
            end

            RUN: begin
                ctrl.busy     = 1'b1;
                ctrl.in_valid = 1'b1;

                // Generate current butterfly addresses
                ctrl.rd_addrA = group_base + j_cnt;
                ctrl.rd_addrB = ctrl.rd_addrA + stride;

                // Twiddle index = j within group (0 .. stride-1)
                ctrl.twiddle_idx = exp[N_LOG2_P-2:0];

                // When we've issued the last butterfly of this stage, go flush
                if (last_butterfly) begin
                    NS = FLUSH;
                end
            end

            FLUSH: begin
                ctrl.busy = 1'b1;
                ctrl.in_valid = 1'b1;
                // ctrl.in_valid = 0 here; no new butterflies issued

                if (flush_cnt == 0) begin
                    if (stage_reg == (N_LOG2_P-1))
                        NS = DONE;  // last stage finished
                    else
                        NS = RUN;   // next stage
                end
            end

            DONE: begin
                ctrl.busy = 1'b0;
                ctrl.done = 1'b1;

                // Wait for start to go low before allowing a new run
                if (!ctrl.start)
                    NS = INIT;
            end

            default: NS = INIT;
        endcase
    end

endmodule
