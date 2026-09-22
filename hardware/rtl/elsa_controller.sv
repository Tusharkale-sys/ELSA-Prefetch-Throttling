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
    output logic [1:0]   current_action,
    output logic [3:0]   current_degree,

    output logic         epoch_update_pulse,

    output logic [63:0]  epoch_pref_issued,
    output logic [63:0]  epoch_pref_useful
);

    localparam integer NUM_STATES    = 8;
    localparam integer NUM_ACTIONS   = 4;
    localparam integer TRACK_ENTRIES = 64;
    localparam integer WIDE_WIDTH    = 96;

    logic signed [Q_WIDTH-1:0]
        q_table [0:NUM_STATES-1][0:NUM_ACTIONS-1];

    logic [2:0] rl_state;
    logic [1:0] rl_action;
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

    integer ai;

    logic [1:0] next_action_comb;

    logic signed [Q_WIDTH-1:0]
        best_q_comb;

    always_comb begin
        next_action_comb = 2'd0;

        best_q_comb =
            q_table[next_state_comb][0];

        for (
            ai = 1;
            ai < NUM_ACTIONS;
            ai = ai + 1
        ) begin

            if (
                q_table[next_state_comb][ai]
                >
                best_q_comb
            ) begin

                best_q_comb =
                    q_table[next_state_comb][ai];

                next_action_comb =
                    ai;
            end
        end
    end

    function automatic logic [3:0]
    degree_from_action(
        input logic [1:0] action
    );
        begin
            case (action)
                2'd0:
                    degree_from_action = 4'd1;

                2'd1:
                    degree_from_action = 4'd2;

                2'd2:
                    degree_from_action = 4'd4;

                default:
                    degree_from_action = 4'd8;
            endcase
        end
    endfunction

    logic signed [WIDE_WIDTH-1:0]
        useful_rate_wide;

    logic signed [WIDE_WIDTH-1:0]
        previous_rate_wide;

    logic signed [WIDE_WIDTH-1:0]
        reward_wide;

    logic signed [WIDE_WIDTH-1:0]
        penalty_wide;

    logic signed [WIDE_WIDTH-1:0]
        q_old_wide;

    logic signed [WIDE_WIDTH-1:0]
        q_next_wide;

    logic signed [WIDE_WIDTH-1:0]
        gamma_term_wide;

    logic signed [WIDE_WIDTH-1:0]
        target_wide;

    logic signed [WIDE_WIDTH-1:0]
        delta_wide;

    logic signed [WIDE_WIDTH-1:0]
        q_updated_wide;

    logic signed [Q_WIDTH-1:0]
        useful_rate_fp_comb;

    logic signed [Q_WIDTH-1:0]
        q_updated_comb;

    always_comb begin
        useful_rate_wide =
            $signed(
                {1'b0, epoch_useful_count}
            );

        useful_rate_wide =
            (useful_rate_wide <<< Q_FRAC)
            /
            EPOCH_LEN;

        useful_rate_fp_comb =
            useful_rate_wide[Q_WIDTH-1:0];

        previous_rate_wide =
            $signed(prev_useful_rate_fp);

        reward_wide =
            (
                useful_rate_wide
                -
                previous_rate_wide
            )
            *
            100;

        penalty_wide =
            $signed({1'b0, rl_degree});

        penalty_wide =
            penalty_wide * 5;

        penalty_wide =
            penalty_wide <<< Q_FRAC;

        if (bw_level >= 8'd3)
            reward_wide =
                reward_wide
                -
                penalty_wide;

        q_old_wide =
            $signed(
                q_table
                    [rl_state]
                    [rl_action]
            );

        q_next_wide =
            $signed(
                q_table
                    [next_state_comb]
                    [next_action_comb]
            );

        gamma_term_wide =
            (q_next_wide * 3) / 5;

        target_wide =
            reward_wide
            +
            gamma_term_wide;

        delta_wide =
            target_wide
            -
            q_old_wide;

        q_updated_wide =
            q_old_wide
            +
            (delta_wide / 2);

        q_updated_comb =
            q_updated_wide[Q_WIDTH-1:0];
    end

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
                t = 0;
                t < TRACK_ENTRIES;
                t = t + 1
            )
                track_table[t] <= 64'd0;

            rl_state <= 3'd0;

            rl_action <= 2'd1;

            rl_degree <= 4'd8;

            access_counter <= 64'd0;

            bw_level <= 8'd0;

            pref_issued <= 64'd0;

            pref_useful <= 64'd0;

            prev_useful_rate_fp <= '0;

            epoch_update_pulse <= 1'b0;

        end else begin

            epoch_update_pulse <= 1'b0;

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

                    q_table
                        [rl_state]
                        [rl_action]
                    <=
                        q_updated_comb;

                    rl_state <=
                        next_state_comb;

                    rl_action <=
                        next_action_comb;

                    rl_degree <=
                        degree_from_action(
                            next_action_comb
                        );

                    prev_useful_rate_fp <=
                        useful_rate_fp_comb;

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
