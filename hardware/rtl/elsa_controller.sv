`timescale 1ns/1ps

module elsa_controller #(
    parameter integer EPOCH_LEN  = 1024,
    parameter integer Q_WIDTH    = 64,
    parameter integer Q_FRAC     = 24,
    parameter integer LINE_SHIFT = 6
)(
    input  logic         clk,
    input  logic         rst_n,

    input  logic         rl_enable,

    input  logic         access_valid,
    input  logic [63:0]  demand_addr,

    input  logic         prefetch_issue_valid,
    input  logic [63:0]  prefetch_addr,

    input  logic         bw_update_valid,
    input  logic [7:0]   bw_level_in,

    input  logic [3:0]   natural_degree,

    output logic [3:0]   capped_degree,

    output logic [2:0]   current_state,
    output logic [2:0]   current_action,
    output logic [3:0]   current_degree,

    output logic         epoch_update_pulse,

    output logic [63:0]  epoch_pref_issued,
    output logic [63:0]  epoch_pref_useful
);

    localparam integer NUM_STATES    = 8;
    localparam integer NUM_ACTIONS   = 5;
    localparam integer TRACK_ENTRIES = 64;
    localparam integer WIDE_WIDTH    = 96;

    logic signed [Q_WIDTH-1:0]
        q_table [0:NUM_STATES-1][0:NUM_ACTIONS-1];

    logic [2:0] rl_state;
    logic [2:0] rl_action;
    logic [3:0] rl_degree;

    logic [63:0] access_counter;
    logic [7:0]  bw_level;

    logic [63:0] pref_issued;
    logic [63:0] pref_useful;

    logic signed [Q_WIDTH-1:0]
        prev_useful_rate_fp;

    logic [63:0]
        track_table [0:TRACK_ENTRIES-1];

    logic [63:0] demand_line;
    logic [5:0]  demand_index;
    logic        demand_useful_hit;

    logic [63:0] prefetch_line;
    logic [5:0]  prefetch_index;

    logic        epoch_boundary;
    logic [63:0] epoch_useful_count;

    assign demand_line =
        demand_addr >> LINE_SHIFT;

    assign demand_index =
        demand_line[5:0];

    assign demand_useful_hit =
        access_valid &&
        (demand_line != 64'd0) &&
        (track_table[demand_index] == demand_line);

    assign prefetch_line =
        prefetch_addr >> LINE_SHIFT;

    assign prefetch_index =
        prefetch_line[5:0];

    assign epoch_boundary =
        access_valid &&
        ((access_counter + 64'd1) >= EPOCH_LEN);

    assign epoch_useful_count =
        pref_useful +
        (demand_useful_hit ? 64'd1 : 64'd0);

    always_comb begin
        if (!rl_enable)
            capped_degree = natural_degree;
        else if (natural_degree > rl_degree)
            capped_degree = rl_degree;
        else
            capped_degree = natural_degree;
    end

    logic [1:0] accuracy_bucket;

    logic [65:0] useful_x4;
    logic [65:0] useful_x2;
    logic [65:0] issued_x1;
    logic [65:0] issued_x3;

    logic [2:0] next_state_comb;

    always_comb begin
        useful_x4 =
            {2'b00, epoch_useful_count} << 2;

        useful_x2 =
            {2'b00, epoch_useful_count} << 1;

        issued_x1 =
            {2'b00, pref_issued};

        issued_x3 =
            {2'b00, pref_issued}
            +
            ({2'b00, pref_issued} << 1);

        if (pref_issued == 64'd0)
            accuracy_bucket = 2'd0;

        else if (useful_x4 < issued_x1)
            accuracy_bucket = 2'd0;

        else if (useful_x2 < issued_x1)
            accuracy_bucket = 2'd1;

        else if (useful_x4 < issued_x3)
            accuracy_bucket = 2'd2;

        else
            accuracy_bucket = 2'd3;

        next_state_comb =
            {accuracy_bucket, 1'b0}
            +
            ((rl_degree > 4'd2) ? 3'd1 : 3'd0);
    end

    /*
     * Fast-path cached argmax.
     *
     * Invariant before every epoch boundary:
     *   cache[state] == direct strict-'>' scan of Q[state][0..4].
     *
     * All-zero rows therefore select action 0 exactly as frozen NEW5.
     */
    logic [2:0]
        best_action_cache [0:NUM_STATES-1];

    logic signed [Q_WIDTH-1:0]
        best_q_cache [0:NUM_STATES-1];

    logic [2:0] next_action_comb;

    logic signed [Q_WIDTH-1:0]
        best_q_comb;

    always_comb begin
        next_action_comb =
            best_action_cache[next_state_comb];

        best_q_comb =
            best_q_cache[next_state_comb];
    end

    function automatic logic [3:0]
    degree_from_action(
        input logic [2:0] action
    );
        begin
            case (action)
                3'd0:
                    degree_from_action = 4'd1;

                3'd1:
                    degree_from_action = 4'd2;

                3'd2:
                    degree_from_action = 4'd4;

                3'd3:
                    degree_from_action = 4'd8;

                3'd4:
                    degree_from_action = 4'd0;

                default:
                    degree_from_action = 4'd0;
            endcase
        end
    endfunction

    /*
     * Background SARSA update engine.
     *
     * The externally visible state/action/degree transition remains
     * on the original epoch boundary.  Only the Q update is deferred.
     */
    localparam logic [3:0] U_IDLE        = 4'd0;
    localparam logic [3:0] U_RATE        = 4'd1;
    localparam logic [3:0] U_REWARD      = 4'd2;
    localparam logic [3:0] U_PENALTY     = 4'd3;
    localparam logic [3:0] U_GAMMA_PREP  = 4'd4;
    localparam logic [3:0] U_DIV_INIT    = 4'd5;
    localparam logic [3:0] U_DIV_STEP    = 4'd6;
    localparam logic [3:0] U_DIV_FINAL   = 4'd7;
    localparam logic [3:0] U_TARGET      = 4'd8;
    localparam logic [3:0] U_DELTA       = 4'd9;
    localparam logic [3:0] U_UPDATE      = 4'd10;
    localparam logic [3:0] U_COMMIT      = 4'd11;
    localparam logic [3:0] U_SCAN_INIT   = 4'd12;
    localparam logic [3:0] U_SCAN_STEP   = 4'd13;

    logic [3:0] update_state;
    logic [7:0] update_age;

    logic update_overlap_error;
    logic update_latency_error;

    logic [2:0] pending_state;
    logic [2:0] pending_action;

    logic [63:0] snap_useful_count;

    logic signed [Q_WIDTH-1:0]
        snap_prev_rate;

    logic signed [Q_WIDTH-1:0]
        snap_q_old;

    logic signed [Q_WIDTH-1:0]
        snap_q_next;

    logic [3:0] snap_degree;
    logic [7:0] snap_bw;

    logic signed [WIDE_WIDTH-1:0]
        useful_rate_reg;

    logic signed [WIDE_WIDTH-1:0]
        reward_reg;

    logic signed [WIDE_WIDTH-1:0]
        reward_adjusted_reg;

    logic signed [WIDE_WIDTH-1:0]
        gamma_num_reg;

    logic signed [WIDE_WIDTH-1:0]
        gamma_term_reg;

    logic signed [WIDE_WIDTH-1:0]
        target_reg;

    logic signed [WIDE_WIDTH-1:0]
        delta_reg;

    logic signed [WIDE_WIDTH-1:0]
        q_updated_reg;

    /*
     * Exact restoring divider for |3*Qnext| / 5.
     *
     * The sign is restored after unsigned division.  Therefore the
     * result is exact signed truncation toward zero, matching Verilog
     * signed '/' semantics.
     */
    logic [WIDE_WIDTH-1:0] div_dividend;
    logic [WIDE_WIDTH-1:0] div_quotient;
    logic [2:0]            div_remainder;
    logic [6:0]            div_count;
    logic                  div_negative;

    logic [3:0] div_trial;
    logic       div_qbit;

    assign div_trial =
        {div_remainder, div_dividend[WIDE_WIDTH-1]};

    assign div_qbit =
        (div_trial >= 4'd5);

    /*
     * Serial exact cache repair for the one modified Q row.
     */
    logic [2:0] scan_action;
    logic [2:0] scan_best_action;

    logic signed [Q_WIDTH-1:0]
        scan_best_q;

    /*
     * H7 static-state decode.
     *
     * pending_state is decoded explicitly so synthesis never
     * needs to form a flattened variable Q-row address from
     * pending_state * NUM_ACTIONS.
     *
     * The action index remains unchanged inside the selected
     * constant row.
     */
    logic signed [Q_WIDTH-1:0]
        pending_q0_static;

    logic signed [Q_WIDTH-1:0]
        pending_scan_q_static;

    always_comb begin
        pending_q0_static = '0;
        pending_scan_q_static = '0;

        case (pending_state)

            3'd0: begin
                pending_q0_static =
                    q_table[0][0];

                pending_scan_q_static =
                    q_table[0][scan_action];
            end

            3'd1: begin
                pending_q0_static =
                    q_table[1][0];

                pending_scan_q_static =
                    q_table[1][scan_action];
            end

            3'd2: begin
                pending_q0_static =
                    q_table[2][0];

                pending_scan_q_static =
                    q_table[2][scan_action];
            end

            3'd3: begin
                pending_q0_static =
                    q_table[3][0];

                pending_scan_q_static =
                    q_table[3][scan_action];
            end

            3'd4: begin
                pending_q0_static =
                    q_table[4][0];

                pending_scan_q_static =
                    q_table[4][scan_action];
            end

            3'd5: begin
                pending_q0_static =
                    q_table[5][0];

                pending_scan_q_static =
                    q_table[5][scan_action];
            end

            3'd6: begin
                pending_q0_static =
                    q_table[6][0];

                pending_scan_q_static =
                    q_table[6][scan_action];
            end

            3'd7: begin
                pending_q0_static =
                    q_table[7][0];

                pending_scan_q_static =
                    q_table[7][scan_action];
            end

            default: begin
                pending_q0_static = '0;
                pending_scan_q_static = '0;
            end

        endcase
    end

    logic update_busy;

    assign update_busy =
        (update_state != U_IDLE);

    integer s;
    integer a;
    integer t;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin

            for (
                s = 0;
                s < NUM_STATES;
                s = s + 1
            )
                for (
                    a = 0;
                    a < NUM_ACTIONS;
                    a = a + 1
                )
                    q_table[s][a] <= '0;

            for (
                s = 0;
                s < NUM_STATES;
                s = s + 1
            ) begin
                best_action_cache[s] <= 3'd0;
                best_q_cache[s] <= '0;
            end

            for (
                t = 0;
                t < TRACK_ENTRIES;
                t = t + 1
            )
                track_table[t] <= 64'd0;

            rl_state <= 3'd0;

            rl_action <= 3'd1;

            rl_degree <= 4'd8;

            access_counter <= 64'd0;

            bw_level <= 8'd0;

            pref_issued <= 64'd0;

            pref_useful <= 64'd0;

            prev_useful_rate_fp <= '0;

            update_state <= U_IDLE;
            update_age <= 8'd0;

            update_overlap_error <= 1'b0;
            update_latency_error <= 1'b0;

            pending_state <= 3'd0;
            pending_action <= 3'd0;

            snap_useful_count <= 64'd0;
            snap_prev_rate <= '0;
            snap_q_old <= '0;
            snap_q_next <= '0;
            snap_degree <= 4'd0;
            snap_bw <= 8'd0;

            useful_rate_reg <= '0;
            reward_reg <= '0;
            reward_adjusted_reg <= '0;
            gamma_num_reg <= '0;
            gamma_term_reg <= '0;
            target_reg <= '0;
            delta_reg <= '0;
            q_updated_reg <= '0;

            div_dividend <= '0;
            div_quotient <= '0;
            div_remainder <= 3'd0;
            div_count <= 7'd0;
            div_negative <= 1'b0;

            scan_action <= 3'd0;
            scan_best_action <= 3'd0;
            scan_best_q <= '0;

            epoch_update_pulse <= 1'b0;

        end else begin

            epoch_update_pulse <= 1'b0;

            /*
             * Background update engine.
             *
             * A boundary starts U_RATE only when the previous update
             * is complete.  The H2 latency contract guarantees this
             * under one-access-per-cycle operation.
             */
            if (update_state != U_IDLE) begin
                if (update_age < 8'hff)
                    update_age <= update_age + 8'd1;

                if (update_age >= 8'd127)
                    update_latency_error <= 1'b1;
            end

            case (update_state)

                U_IDLE: begin
                    update_age <= 8'd0;
                end

                U_RATE: begin
                    /*
                     * Exact frozen expression:
                     *
                     *   useful_rate =
                     *     (epoch_useful << Q_FRAC) / EPOCH_LEN
                     *
                     * EPOCH_LEN remains the frozen 1024 parameter.
                     */
                    useful_rate_reg <=
                        (
                            $signed(
                                {
                                    {(WIDE_WIDTH-64){1'b0}},
                                    snap_useful_count
                                }
                            )
                            <<< Q_FRAC
                        )
                        /
                        EPOCH_LEN;

                    update_state <= U_REWARD;
                end

                U_REWARD: begin
                    prev_useful_rate_fp <=
                        useful_rate_reg[Q_WIDTH-1:0];

                    reward_reg <=
                        (
                            useful_rate_reg
                            -
                            $signed(
                                {
                                    {(WIDE_WIDTH-Q_WIDTH){
                                        snap_prev_rate[Q_WIDTH-1]
                                    }},
                                    snap_prev_rate
                                }
                            )
                        )
                        *
                        100;

                    update_state <= U_PENALTY;
                end

                U_PENALTY: begin
                    if (snap_bw >= 8'd3)
                        reward_adjusted_reg <=
                            reward_reg
                            -
                            (
                                (
                                    $signed(
                                        {
                                            {(WIDE_WIDTH-4){1'b0}},
                                            snap_degree
                                        }
                                    )
                                    *
                                    5
                                )
                                <<< Q_FRAC
                            );
                    else
                        reward_adjusted_reg <=
                            reward_reg;

                    update_state <= U_GAMMA_PREP;
                end

                U_GAMMA_PREP: begin
                    gamma_num_reg <=
                        $signed(
                            {
                                {(WIDE_WIDTH-Q_WIDTH){
                                    snap_q_next[Q_WIDTH-1]
                                }},
                                snap_q_next
                            }
                        )
                        *
                        3;

                    update_state <= U_DIV_INIT;
                end

                U_DIV_INIT: begin
                    div_negative <=
                        gamma_num_reg[WIDE_WIDTH-1];

                    if (gamma_num_reg[WIDE_WIDTH-1])
                        div_dividend <=
                            $unsigned(-gamma_num_reg);
                    else
                        div_dividend <=
                            $unsigned(gamma_num_reg);

                    div_quotient <= '0;
                    div_remainder <= 3'd0;
                    div_count <= 7'd0;

                    update_state <= U_DIV_STEP;
                end

                U_DIV_STEP: begin
                    div_dividend <=
                        {
                            div_dividend[WIDE_WIDTH-2:0],
                            1'b0
                        };

                    div_quotient <=
                        {
                            div_quotient[WIDE_WIDTH-2:0],
                            div_qbit
                        };

                    if (div_qbit)
                        div_remainder <=
                            div_trial - 4'd5;
                    else
                        div_remainder <=
                            div_trial[2:0];

                    if (div_count == WIDE_WIDTH-1) begin
                        update_state <= U_DIV_FINAL;
                    end else begin
                        div_count <=
                            div_count + 7'd1;
                    end
                end

                U_DIV_FINAL: begin
                    if (div_negative)
                        gamma_term_reg <=
                            -$signed(div_quotient);
                    else
                        gamma_term_reg <=
                            $signed(div_quotient);

                    update_state <= U_TARGET;
                end

                U_TARGET: begin
                    target_reg <=
                        reward_adjusted_reg
                        +
                        gamma_term_reg;

                    update_state <= U_DELTA;
                end

                U_DELTA: begin
                    delta_reg <=
                        target_reg
                        -
                        $signed(
                            {
                                {(WIDE_WIDTH-Q_WIDTH){
                                    snap_q_old[Q_WIDTH-1]
                                }},
                                snap_q_old
                            }
                        );

                    update_state <= U_UPDATE;
                end

                U_UPDATE: begin
                    /*
                     * Exact signed /2 truncation toward zero.
                     *
                     * For a negative odd value x, arithmetic >>>1
                     * rounds toward -infinity.  (x+1)>>>1 instead
                     * implements truncation toward zero.
                     */
                    if (delta_reg[WIDE_WIDTH-1])
                        q_updated_reg <=
                            $signed(
                                {
                                    {(WIDE_WIDTH-Q_WIDTH){
                                        snap_q_old[Q_WIDTH-1]
                                    }},
                                    snap_q_old
                                }
                            )
                            +
                            (
                                (delta_reg + 96'sd1)
                                >>> 1
                            );
                    else
                        q_updated_reg <=
                            $signed(
                                {
                                    {(WIDE_WIDTH-Q_WIDTH){
                                        snap_q_old[Q_WIDTH-1]
                                    }},
                                    snap_q_old
                                }
                            )
                            +
                            (delta_reg >>> 1);

                    update_state <= U_COMMIT;
                end

                U_COMMIT: begin
                    case (pending_state)

                        3'd0:
                            q_table[0][pending_action] <=
                                q_updated_reg[Q_WIDTH-1:0];

                        3'd1:
                            q_table[1][pending_action] <=
                                q_updated_reg[Q_WIDTH-1:0];

                        3'd2:
                            q_table[2][pending_action] <=
                                q_updated_reg[Q_WIDTH-1:0];

                        3'd3:
                            q_table[3][pending_action] <=
                                q_updated_reg[Q_WIDTH-1:0];

                        3'd4:
                            q_table[4][pending_action] <=
                                q_updated_reg[Q_WIDTH-1:0];

                        3'd5:
                            q_table[5][pending_action] <=
                                q_updated_reg[Q_WIDTH-1:0];

                        3'd6:
                            q_table[6][pending_action] <=
                                q_updated_reg[Q_WIDTH-1:0];

                        3'd7:
                            q_table[7][pending_action] <=
                                q_updated_reg[Q_WIDTH-1:0];

                        default: begin
                        end

                    endcase

                    update_state <= U_SCAN_INIT;
                end

                U_SCAN_INIT: begin
                    /*
                     * Commit occurred on the previous edge, so this
                     * read sees the newly updated Q row.
                     */
                    scan_action <= 3'd1;
                    scan_best_action <= 3'd0;
                    scan_best_q <=
                        pending_q0_static;

                    update_state <= U_SCAN_STEP;
                end

                U_SCAN_STEP: begin
                    if (
                        pending_scan_q_static
                        >
                        scan_best_q
                    ) begin

                        if (scan_action == 3'd4) begin
                            case (pending_state)

                                3'd0: begin
                                    best_q_cache[0] <=
                                        pending_scan_q_static;
                                    best_action_cache[0] <=
                                        scan_action;
                                end

                                3'd1: begin
                                    best_q_cache[1] <=
                                        pending_scan_q_static;
                                    best_action_cache[1] <=
                                        scan_action;
                                end

                                3'd2: begin
                                    best_q_cache[2] <=
                                        pending_scan_q_static;
                                    best_action_cache[2] <=
                                        scan_action;
                                end

                                3'd3: begin
                                    best_q_cache[3] <=
                                        pending_scan_q_static;
                                    best_action_cache[3] <=
                                        scan_action;
                                end

                                3'd4: begin
                                    best_q_cache[4] <=
                                        pending_scan_q_static;
                                    best_action_cache[4] <=
                                        scan_action;
                                end

                                3'd5: begin
                                    best_q_cache[5] <=
                                        pending_scan_q_static;
                                    best_action_cache[5] <=
                                        scan_action;
                                end

                                3'd6: begin
                                    best_q_cache[6] <=
                                        pending_scan_q_static;
                                    best_action_cache[6] <=
                                        scan_action;
                                end

                                3'd7: begin
                                    best_q_cache[7] <=
                                        pending_scan_q_static;
                                    best_action_cache[7] <=
                                        scan_action;
                                end

                                default: begin
                                end

                            endcase
                        end else begin
                            scan_best_q <=
                                pending_scan_q_static;

                            scan_best_action <=
                                scan_action;
                        end

                    end else if (scan_action == 3'd4) begin
                        case (pending_state)

                            3'd0: begin
                                best_q_cache[0] <=
                                    scan_best_q;
                                best_action_cache[0] <=
                                    scan_best_action;
                            end

                            3'd1: begin
                                best_q_cache[1] <=
                                    scan_best_q;
                                best_action_cache[1] <=
                                    scan_best_action;
                            end

                            3'd2: begin
                                best_q_cache[2] <=
                                    scan_best_q;
                                best_action_cache[2] <=
                                    scan_best_action;
                            end

                            3'd3: begin
                                best_q_cache[3] <=
                                    scan_best_q;
                                best_action_cache[3] <=
                                    scan_best_action;
                            end

                            3'd4: begin
                                best_q_cache[4] <=
                                    scan_best_q;
                                best_action_cache[4] <=
                                    scan_best_action;
                            end

                            3'd5: begin
                                best_q_cache[5] <=
                                    scan_best_q;
                                best_action_cache[5] <=
                                    scan_best_action;
                            end

                            3'd6: begin
                                best_q_cache[6] <=
                                    scan_best_q;
                                best_action_cache[6] <=
                                    scan_best_action;
                            end

                            3'd7: begin
                                best_q_cache[7] <=
                                    scan_best_q;
                                best_action_cache[7] <=
                                    scan_best_action;
                            end

                            default: begin
                            end

                        endcase
                    end

                    if (scan_action == 3'd4) begin
                        update_state <= U_IDLE;
                    end else begin
                        scan_action <=
                            scan_action + 3'd1;
                    end
                end

                default: begin
                    update_state <= U_IDLE;
                    update_overlap_error <= 1'b1;
                end

            endcase

            if (bw_update_valid)
                bw_level <= bw_level_in;

            if (demand_useful_hit)
                track_table[demand_index] <= 64'd0;

            if (prefetch_issue_valid)
                track_table[prefetch_index] <=
                    prefetch_line;

            if (access_valid) begin

                if (epoch_boundary) begin

                    access_counter <= 64'd0;

                    /*
                     * Frozen NEW5 chooses next_action from the
                     * PRE-UPDATE Q table.  The cache therefore drives
                     * the immediate boundary decision, while all data
                     * required for the old-state SARSA write is
                     * snapshotted for background execution.
                     */
                    if (update_state != U_IDLE) begin
                        update_overlap_error <= 1'b1;
                    end else begin
                        pending_state <=
                            rl_state;

                        pending_action <=
                            rl_action;

                        snap_useful_count <=
                            epoch_useful_count;

                        snap_prev_rate <=
                            prev_useful_rate_fp;

                        snap_degree <=
                            rl_degree;

                        snap_bw <=
                            bw_level;

                        snap_q_old <=
                            q_table
                                [rl_state]
                                [rl_action];

                        snap_q_next <=
                            best_q_comb;

                        update_state <=
                            U_RATE;

                        update_age <=
                            8'd0;
                    end

                    rl_state <=
                        next_state_comb;

                    rl_action <=
                        next_action_comb;

                    rl_degree <=
                        degree_from_action(
                            next_action_comb
                        );

                    /*
                     * prev_useful_rate_fp is committed by the
                     * background engine before the next epoch.
                     */

                    pref_useful <= 64'd0;

                    if (prefetch_issue_valid)
                        pref_issued <= 64'd1;
                    else
                        pref_issued <= 64'd0;

                    epoch_update_pulse <= 1'b1;

                end else begin

                    access_counter <=
                        access_counter + 64'd1;

                    if (demand_useful_hit)
                        pref_useful <=
                            pref_useful + 64'd1;

                    if (prefetch_issue_valid)
                        pref_issued <=
                            pref_issued + 64'd1;
                end

            end else begin

                if (prefetch_issue_valid)
                    pref_issued <=
                        pref_issued + 64'd1;
            end
        end
    end

    assign current_state =
        rl_state;

    assign current_action =
        rl_action;

    assign current_degree =
        rl_degree;

    assign epoch_pref_issued =
        pref_issued;

    assign epoch_pref_useful =
        pref_useful;

endmodule
