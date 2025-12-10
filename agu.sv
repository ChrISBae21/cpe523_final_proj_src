import fft_consts::*;

module address_gen_unit (
    agu_if.fsm ctrl
);

    localparam int N_LOG2_P = N_LOG2;
    localparam int N_P      = 1 << N_LOG2_P;

    // FSM states
    typedef enum logic [1:0] {
        INIT,   // idle / waiting for start
        RUN,    // iterating butterflies over all stages
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

    logic                 last_j;
    logic                 last_group;
    logic                 last_butterfly;

    // Ping-pong bank select (toggles once per stage)
    logic bank_sel_reg;

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
    // Sequential counters and bank_sel
    // ------------------------------------------------------------
    always_ff @(posedge ctrl.clk) begin
        if (!ctrl.rst_n) begin
            stage_reg   <= '0;
            group_cnt   <= '0;
            j_cnt       <= '0;
            bank_sel_reg<= 1'b0;
        end else begin
            case (PS)
                INIT: begin
                    if (ctrl.start) begin
                        stage_reg    <= '0;
                        group_cnt    <= '0;
                        j_cnt        <= '0;
                        bank_sel_reg <= 1'b0;  // start with A->read, B->write
                    end
                end

                RUN: begin
                    if (last_butterfly) begin
                        // Finished all butterflies in this stage
                        if (stage_reg != (N_LOG2_P-1)) begin
                            // move to next stage
                            stage_reg    <= stage_reg + 1;
                            group_cnt    <= '0;
                            j_cnt        <= '0;
                            bank_sel_reg <= ~bank_sel_reg; // swap banks
                        end
                        // else: last stage, counters stay where they are
                    end else if (last_j) begin
                        // End of this group, move to next group
                        j_cnt     <= '0;
                        group_cnt <= group_cnt + 1;
                    end else begin
                        // Next butterfly within the same group
                        j_cnt     <= j_cnt + 1;
                    end
                end

                DONE: begin
                    // hold stage_reg/bank_sel_reg until next start
                end

                default: ;
            endcase
        end
    end

    // ------------------------------------------------------------
    // Next-state and outputs (like your CU_FSM style)
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
            // ----------------------------------------------------
            // INIT: wait for start
            // ----------------------------------------------------
            INIT: begin
                ctrl.busy = 1'b0;
                ctrl.done = 1'b0;

                if (ctrl.start) begin
                    NS = RUN;
                end
            end

            // ----------------------------------------------------
            // RUN: generate addresses for all stages
            // ----------------------------------------------------
            RUN: begin
                ctrl.busy     = 1'b1;
                ctrl.in_valid = 1'b1;

                // Generate current butterfly addresses
                ctrl.rd_addrA = group_base + j_cnt;
                ctrl.rd_addrB = ctrl.rd_addrA + stride;

                // Twiddle index is butterfly index within group
                // Range: 0 .. stride-1, fits in N_LOG2-1 bits
                ctrl.twiddle_idx = j_cnt[N_LOG2_P-2:0];

                // State transitions
                if (last_butterfly && (stage_reg == (N_LOG2_P-1))) begin
                    // Last butterfly of last stage
                    NS = DONE;
                end
            end

            // ----------------------------------------------------
            // DONE: one-shot done pulse; wait for start to drop
            // ----------------------------------------------------
            DONE: begin
                ctrl.busy = 1'b0;
                ctrl.done = 1'b1;

                // Require start to go low before we allow a new run
                if (!ctrl.start)
                    NS = INIT;
            end

            default: NS = INIT;
        endcase
    end

endmodule
