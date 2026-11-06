`timescale 1ns/1ps

module tb_h4;

localparam integer EPOCH_LEN = 1024;

logic clk;
logic rst_n;
logic rl_enable;

logic access_valid;
logic [63:0] demand_addr;

logic prefetch_issue_valid;
logic [63:0] prefetch_addr;

logic bw_update_valid;
logic [7:0] bw_level_in;

logic [3:0] natural_degree;

logic [3:0] capped_ref;
logic [3:0] capped_opt;

logic [2:0] state_ref;
logic [2:0] state_opt;

logic [2:0] action_ref;
logic [2:0] action_opt;

logic [3:0] degree_ref;
logic [3:0] degree_opt;

logic pulse_ref;
logic pulse_opt;

logic [63:0] issued_ref;
logic [63:0] issued_opt;

logic [63:0] useful_ref;
logic [63:0] useful_opt;

integer fd;
integer rc;

integer epoch_id;
integer issued_i;
integer useful_i;
integer bw_i;

integer exp_state_i;
integer exp_action_i;
integer exp_degree_i;

integer upd_state_i;
integer upd_action_i;

logic [63:0] exp_q_bits;

integer vector_count;

integer replay_external_mismatches;
integer replay_q_mismatches;
integer replay_cache_mismatches;
integer replay_expected_mismatches;

integer stress_external_mismatches;
integer stress_q_mismatches;
integer stress_cache_mismatches;

integer total_mismatches;

integer action4_degree0_count;

integer replay_max_latency;
integer stress_max_latency;

integer stress_boundaries;

integer phase;

integer j;
integer latency_now;
integer stress_cycle;

string vector_path;

logic [63:0] line_value;

elsa_controller_ref #(
    .EPOCH_LEN(EPOCH_LEN),
    .Q_WIDTH(64),
    .Q_FRAC(24),
    .LINE_SHIFT(6)
) ref_dut (
    .clk(clk),
    .rst_n(rst_n),
    .rl_enable(rl_enable),
    .access_valid(access_valid),
    .demand_addr(demand_addr),
    .prefetch_issue_valid(prefetch_issue_valid),
    .prefetch_addr(prefetch_addr),
    .bw_update_valid(bw_update_valid),
    .bw_level_in(bw_level_in),
    .natural_degree(natural_degree),
    .capped_degree(capped_ref),
    .current_state(state_ref),
    .current_action(action_ref),
    .current_degree(degree_ref),
    .epoch_update_pulse(pulse_ref),
    .epoch_pref_issued(issued_ref),
    .epoch_pref_useful(useful_ref)
);

elsa_controller_opt #(
    .EPOCH_LEN(EPOCH_LEN),
    .Q_WIDTH(64),
    .Q_FRAC(24),
    .LINE_SHIFT(6)
) opt_dut (
    .clk(clk),
    .rst_n(rst_n),
    .rl_enable(rl_enable),
    .access_valid(access_valid),
    .demand_addr(demand_addr),
    .prefetch_issue_valid(prefetch_issue_valid),
    .prefetch_addr(prefetch_addr),
    .bw_update_valid(bw_update_valid),
    .bw_level_in(bw_level_in),
    .natural_degree(natural_degree),
    .capped_degree(capped_opt),
    .current_state(state_opt),
    .current_action(action_opt),
    .current_degree(degree_opt),
    .epoch_update_pulse(pulse_opt),
    .epoch_pref_issued(issued_opt),
    .epoch_pref_useful(useful_opt)
);

initial clk = 1'b0;
always #5 clk = ~clk;

task automatic add_external_mismatch;
begin
    if (phase == 0)
        replay_external_mismatches =
            replay_external_mismatches + 1;
    else
        stress_external_mismatches =
            stress_external_mismatches + 1;

    total_mismatches =
        total_mismatches + 1;
end
endtask

task automatic add_q_mismatch;
begin
    if (phase == 0)
        replay_q_mismatches =
            replay_q_mismatches + 1;
    else
        stress_q_mismatches =
            stress_q_mismatches + 1;

    total_mismatches =
        total_mismatches + 1;
end
endtask

task automatic add_cache_mismatch;
begin
    if (phase == 0)
        replay_cache_mismatches =
            replay_cache_mismatches + 1;
    else
        stress_cache_mismatches =
            stress_cache_mismatches + 1;

    total_mismatches =
        total_mismatches + 1;
end
endtask

task automatic guard;
begin
    if (total_mismatches > 20) begin
        $display(
            "H4_FAIL=TOO_MANY_MISMATCHES count=%0d",
            total_mismatches
        );
        $finish;
    end
end
endtask

task automatic compare_external(
    input integer tag
);
begin

    if (capped_opt !== capped_ref) begin
        $display(
            "H4_EXT_MISMATCH=tag:%0d field:capped opt:%0d ref:%0d",
            tag, capped_opt, capped_ref
        );
        add_external_mismatch();
    end

    if (state_opt !== state_ref) begin
        $display(
            "H4_EXT_MISMATCH=tag:%0d field:state opt:%0d ref:%0d",
            tag, state_opt, state_ref
        );
        add_external_mismatch();
    end

    if (action_opt !== action_ref) begin
        $display(
            "H4_EXT_MISMATCH=tag:%0d field:action opt:%0d ref:%0d",
            tag, action_opt, action_ref
        );
        add_external_mismatch();
    end

    if (degree_opt !== degree_ref) begin
        $display(
            "H4_EXT_MISMATCH=tag:%0d field:degree opt:%0d ref:%0d",
            tag, degree_opt, degree_ref
        );
        add_external_mismatch();
    end

    if (pulse_opt !== pulse_ref) begin
        $display(
            "H4_EXT_MISMATCH=tag:%0d field:pulse opt:%b ref:%b",
            tag, pulse_opt, pulse_ref
        );
        add_external_mismatch();
    end

    if (issued_opt !== issued_ref) begin
        $display(
            "H4_EXT_MISMATCH=tag:%0d field:issued opt:%0d ref:%0d",
            tag, issued_opt, issued_ref
        );
        add_external_mismatch();
    end

    if (useful_opt !== useful_ref) begin
        $display(
            "H4_EXT_MISMATCH=tag:%0d field:useful opt:%0d ref:%0d",
            tag, useful_opt, useful_ref
        );
        add_external_mismatch();
    end

    guard();
end
endtask

task automatic compare_full_q(
    input integer tag
);
integer s;
integer a;
begin

    for (s = 0; s < 8; s = s + 1) begin
        for (a = 0; a < 5; a = a + 1) begin

            if (
                opt_dut.q_table[s][a]
                !==
                ref_dut.q_table[s][a]
            ) begin

                $display(
                    "H4_Q_MISMATCH=tag:%0d state:%0d action:%0d opt:%h ref:%h",
                    tag,
                    s,
                    a,
                    opt_dut.q_table[s][a],
                    ref_dut.q_table[s][a]
                );

                add_q_mismatch();
            end
        end
    end

    guard();
end
endtask

task automatic check_cache_all(
    input integer tag
);
integer s;
integer a;

reg signed [63:0] best_q;
reg signed [63:0] candidate_q;
reg [2:0] best_action;

begin

    for (s = 0; s < 8; s = s + 1) begin

        best_action = 3'd0;

        best_q =
            $signed(
                opt_dut.q_table[s][0]
            );

        for (a = 1; a < 5; a = a + 1) begin

            candidate_q =
                $signed(
                    opt_dut.q_table[s][a]
                );

            if (candidate_q > best_q) begin
                best_q = candidate_q;
                best_action = a[2:0];
            end
        end

        if (
            opt_dut.best_action_cache[s]
            !==
            best_action
        ) begin

            $display(
                "H4_CACHE_MISMATCH=tag:%0d state:%0d field:action cached:%0d direct:%0d",
                tag,
                s,
                opt_dut.best_action_cache[s],
                best_action
            );

            add_cache_mismatch();
        end

        if (
            opt_dut.best_q_cache[s]
            !==
            best_q
        ) begin

            $display(
                "H4_CACHE_MISMATCH=tag:%0d state:%0d field:q cached:%h direct:%h",
                tag,
                s,
                opt_dut.best_q_cache[s],
                best_q
            );

            add_cache_mismatch();
        end
    end

    guard();
end
endtask

task automatic check_current_decision(
    input integer tag
);
integer a;
integer s;

reg signed [63:0] best_q;
reg signed [63:0] candidate_q;
reg [2:0] best_action;

begin

    s = state_opt;

    best_action = 3'd0;

    best_q =
        $signed(
            opt_dut.q_table[s][0]
        );

    for (a = 1; a < 5; a = a + 1) begin

        candidate_q =
            $signed(
                opt_dut.q_table[s][a]
            );

        if (candidate_q > best_q) begin
            best_q = candidate_q;
            best_action = a[2:0];
        end
    end

    if (action_opt !== best_action) begin
        $display(
            "H4_CACHE_MISMATCH=tag:%0d field:decision action:%0d direct:%0d",
            tag,
            action_opt,
            best_action
        );
        add_cache_mismatch();
    end

    if (
        opt_dut.best_action_cache[s]
        !==
        best_action
    ) begin

        $display(
            "H4_CACHE_MISMATCH=tag:%0d field:selected_cache_action cached:%0d direct:%0d",
            tag,
            opt_dut.best_action_cache[s],
            best_action
        );

        add_cache_mismatch();
    end

    if (
        opt_dut.best_q_cache[s]
        !==
        best_q
    ) begin

        $display(
            "H4_CACHE_MISMATCH=tag:%0d field:selected_cache_q cached:%h direct:%h",
            tag,
            opt_dut.best_q_cache[s],
            best_q
        );

        add_cache_mismatch();
    end

    guard();
end
endtask

task automatic wait_for_opt_idle(
    input integer tag,
    output integer cycles
);
begin

    cycles = 0;

    if (opt_dut.update_state === 4'd0) begin
        $display(
            "H4_ENGINE_MISMATCH=tag:%0d reason:not_busy_after_boundary",
            tag
        );

        total_mismatches =
            total_mismatches + 1;
    end

    while (
        (opt_dut.update_state !== 4'd0)
        &&
        (cycles < 160)
    ) begin

        @(posedge clk);
        #1;

        cycles =
            cycles + 1;

        compare_external(tag);
    end

    if (opt_dut.update_state !== 4'd0) begin

        $display(
            "H4_ENGINE_MISMATCH=tag:%0d reason:latency_timeout cycles:%0d",
            tag,
            cycles
        );

        total_mismatches =
            total_mismatches + 1;
    end

    if (cycles > 128) begin

        $display(
            "H4_ENGINE_MISMATCH=tag:%0d reason:latency_gt_128 cycles:%0d",
            tag,
            cycles
        );

        total_mismatches =
            total_mismatches + 1;
    end

    if (
        opt_dut.update_overlap_error
        !==
        1'b0
    ) begin

        $display(
            "H4_ENGINE_MISMATCH=tag:%0d field:update_overlap_error",
            tag
        );

        total_mismatches =
            total_mismatches + 1;
    end

    if (
        opt_dut.update_latency_error
        !==
        1'b0
    ) begin

        $display(
            "H4_ENGINE_MISMATCH=tag:%0d field:update_latency_error",
            tag
        );

        total_mismatches =
            total_mismatches + 1;
    end

    guard();
end
endtask

task automatic reset_both;
begin

    rst_n = 1'b0;
    rl_enable = 1'b1;

    access_valid = 1'b0;
    demand_addr = 64'd0;

    prefetch_issue_valid = 1'b0;
    prefetch_addr = 64'd0;

    bw_update_valid = 1'b0;
    bw_level_in = 8'd0;

    natural_degree = 4'd8;

    repeat (3)
        @(posedge clk);

    rst_n = 1'b1;

    @(posedge clk);
    #1;

    compare_external(-1);
    check_cache_all(-1);
end
endtask

task automatic pulse_bw(
    input integer bw,
    input integer tag
);
begin

    bw_level_in = bw[7:0];
    bw_update_valid = 1'b1;

    @(posedge clk);
    #1;

    compare_external(tag);

    bw_update_valid = 1'b0;
end
endtask

task automatic issue_line(
    input logic [63:0] line,
    input integer tag
);
begin

    prefetch_addr = line << 6;
    prefetch_issue_valid = 1'b1;

    @(posedge clk);
    #1;

    compare_external(tag);

    prefetch_issue_valid = 1'b0;
end
endtask

task automatic access_line(
    input logic [63:0] line,
    input integer tag
);
begin

    demand_addr = line << 6;
    access_valid = 1'b1;

    @(posedge clk);
    #1;

    compare_external(tag);

    access_valid = 1'b0;
end
endtask

initial begin

    if (
        !$value$plusargs(
            "VECTORS=%s",
            vector_path
        )
    ) begin
        $display(
            "H4_FAIL=VECTOR_PATH_MISSING"
        );
        $finish;
    end

    fd = $fopen(vector_path, "r");

    if (fd == 0) begin
        $display(
            "H4_FAIL=CANNOT_OPEN_VECTOR_FILE"
        );
        $finish;
    end

    vector_count = 0;

    replay_external_mismatches = 0;
    replay_q_mismatches = 0;
    replay_cache_mismatches = 0;
    replay_expected_mismatches = 0;

    stress_external_mismatches = 0;
    stress_q_mismatches = 0;
    stress_cache_mismatches = 0;

    total_mismatches = 0;

    action4_degree0_count = 0;

    replay_max_latency = 0;
    stress_max_latency = 0;

    stress_boundaries = 0;

    phase = 0;

    reset_both();

    /*
     * PHASE A:
     * exact frozen 256-vector replay.
     */

    while (!$feof(fd)) begin

        rc = $fscanf(
            fd,
            "%d %d %d %d %d %d %d %d %d %h\n",
            epoch_id,
            issued_i,
            useful_i,
            bw_i,
            exp_state_i,
            exp_action_i,
            exp_degree_i,
            upd_state_i,
            upd_action_i,
            exp_q_bits
        );

        if (rc == -1)
            break;

        if (rc != 10) begin
            $display(
                "H4_FAIL=VECTOR_PARSE epoch_index:%0d rc:%0d",
                vector_count,
                rc
            );
            $finish;
        end

        pulse_bw(
            bw_i,
            epoch_id
        );

        for (
            j = 0;
            j < issued_i;
            j = j + 1
        ) begin

            line_value =
                64'h0000_0000_0020_0000
                +
                epoch_id * 128
                +
                j
                +
                1;

            issue_line(
                line_value,
                epoch_id
            );
        end

        for (
            j = 0;
            j < useful_i;
            j = j + 1
        ) begin

            line_value =
                64'h0000_0000_0020_0000
                +
                epoch_id * 128
                +
                j
                +
                1;

            access_line(
                line_value,
                epoch_id
            );
        end

        for (
            j = useful_i;
            j < EPOCH_LEN;
            j = j + 1
        ) begin

            line_value =
                64'h0000_0000_1000_0000
                +
                epoch_id * 2048
                +
                j;

            access_line(
                line_value,
                epoch_id
            );
        end

        if (pulse_opt !== 1'b1) begin

            $display(
                "H4_EXPECTED_MISMATCH=epoch:%0d field:pulse got:%b expected:1",
                epoch_id,
                pulse_opt
            );

            replay_expected_mismatches =
                replay_expected_mismatches + 1;

            total_mismatches =
                total_mismatches + 1;
        end

        if (state_opt !== exp_state_i[2:0]) begin

            $display(
                "H4_EXPECTED_MISMATCH=epoch:%0d field:state got:%0d expected:%0d",
                epoch_id,
                state_opt,
                exp_state_i
            );

            replay_expected_mismatches =
                replay_expected_mismatches + 1;

            total_mismatches =
                total_mismatches + 1;
        end

        if (action_opt !== exp_action_i[2:0]) begin

            $display(
                "H4_EXPECTED_MISMATCH=epoch:%0d field:action got:%0d expected:%0d",
                epoch_id,
                action_opt,
                exp_action_i
            );

            replay_expected_mismatches =
                replay_expected_mismatches + 1;

            total_mismatches =
                total_mismatches + 1;
        end

        if (degree_opt !== exp_degree_i[3:0]) begin

            $display(
                "H4_EXPECTED_MISMATCH=epoch:%0d field:degree got:%0d expected:%0d",
                epoch_id,
                degree_opt,
                exp_degree_i
            );

            replay_expected_mismatches =
                replay_expected_mismatches + 1;

            total_mismatches =
                total_mismatches + 1;
        end

        /*
         * Current decision is made from the pre-update Q image.
         */
        check_current_decision(
            epoch_id
        );

        check_cache_all(
            epoch_id
        );

        if (action_opt === 3'd4) begin

            if (
                (degree_opt === 4'd0)
                &&
                (capped_opt === 4'd0)
            ) begin

                action4_degree0_count =
                    action4_degree0_count + 1;

            end else begin

                $display(
                    "H4_EXPECTED_MISMATCH=epoch:%0d field:action4_degree0 action:%0d degree:%0d capped:%0d",
                    epoch_id,
                    action_opt,
                    degree_opt,
                    capped_opt
                );

                replay_expected_mismatches =
                    replay_expected_mismatches + 1;

                total_mismatches =
                    total_mismatches + 1;
            end
        end

        /*
         * Optimized Q write is deliberately deferred.
         * Wait for that internal transaction to finish.
         */
        wait_for_opt_idle(
            epoch_id,
            latency_now
        );

        if (
            latency_now
            >
            replay_max_latency
        )
            replay_max_latency =
                latency_now;

        compare_full_q(
            epoch_id
        );

        check_cache_all(
            epoch_id
        );

        if (
            opt_dut.q_table
                [upd_state_i]
                [upd_action_i]
            !==
            exp_q_bits
        ) begin

            $display(
                "H4_EXPECTED_MISMATCH=epoch:%0d field:opt_q state:%0d action:%0d got:%h expected:%h",
                epoch_id,
                upd_state_i,
                upd_action_i,
                opt_dut.q_table
                    [upd_state_i]
                    [upd_action_i],
                exp_q_bits
            );

            replay_expected_mismatches =
                replay_expected_mismatches + 1;

            total_mismatches =
                total_mismatches + 1;
        end

        if (
            ref_dut.q_table
                [upd_state_i]
                [upd_action_i]
            !==
            exp_q_bits
        ) begin

            $display(
                "H4_EXPECTED_MISMATCH=epoch:%0d field:ref_q state:%0d action:%0d got:%h expected:%h",
                epoch_id,
                upd_state_i,
                upd_action_i,
                ref_dut.q_table
                    [upd_state_i]
                    [upd_action_i],
                exp_q_bits
            );

            replay_expected_mismatches =
                replay_expected_mismatches + 1;

            total_mismatches =
                total_mismatches + 1;
        end

        vector_count =
            vector_count + 1;

        guard();
    end

    $fclose(fd);

    /*
     * PHASE B:
     * one valid access on every clock.
     *
     * 8192 valid clocks = exactly 8 minimum-spacing epochs.
     * +128 clocks keeps the maximum-rate stream active while
     * allowing the final deferred update to finish.
     */

    phase = 1;

    reset_both();

    access_valid = 1'b1;
    prefetch_issue_valid = 1'b0;
    bw_update_valid = 1'b0;
    bw_level_in = 8'd0;
    natural_degree = 4'd8;

    begin : STRESS

        integer busy;
        integer busy_cycles;

        busy = 0;
        busy_cycles = 0;

        for (
            stress_cycle = 1;
            stress_cycle <= 8320;
            stress_cycle = stress_cycle + 1
        ) begin

            demand_addr =
                (
                    64'h0000_0000_4000_0000
                    +
                    stress_cycle
                )
                << 6;

            @(posedge clk);
            #1;

            compare_external(
                stress_cycle
            );

            if (
                opt_dut.update_overlap_error
                !==
                1'b0
            ) begin

                $display(
                    "H4_STRESS_MISMATCH=cycle:%0d field:overlap_error",
                    stress_cycle
                );

                total_mismatches =
                    total_mismatches + 1;
            end

            if (
                opt_dut.update_latency_error
                !==
                1'b0
            ) begin

                $display(
                    "H4_STRESS_MISMATCH=cycle:%0d field:latency_error",
                    stress_cycle
                );

                total_mismatches =
                    total_mismatches + 1;
            end

            /*
             * Finish a prior update before accepting any new
             * epoch-boundary bookkeeping.
             */
            if (busy != 0) begin

                busy_cycles =
                    busy_cycles + 1;

                if (
                    opt_dut.update_state
                    ===
                    4'd0
                ) begin

                    if (
                        busy_cycles
                        >
                        stress_max_latency
                    )
                        stress_max_latency =
                            busy_cycles;

                    if (busy_cycles > 128) begin

                        $display(
                            "H4_STRESS_MISMATCH=cycle:%0d reason:latency_gt_128 latency:%0d",
                            stress_cycle,
                            busy_cycles
                        );

                        total_mismatches =
                            total_mismatches + 1;
                    end

                    compare_full_q(
                        stress_cycle
                    );

                    check_cache_all(
                        stress_cycle
                    );

                    busy = 0;
                    busy_cycles = 0;
                end
            end

            if (pulse_opt === 1'b1) begin

                stress_boundaries =
                    stress_boundaries + 1;

                if (busy != 0) begin

                    $display(
                        "H4_STRESS_MISMATCH=cycle:%0d reason:boundary_while_busy",
                        stress_cycle
                    );

                    total_mismatches =
                        total_mismatches + 1;
                end

                if (
                    opt_dut.update_state
                    ===
                    4'd0
                ) begin

                    $display(
                        "H4_STRESS_MISMATCH=cycle:%0d reason:engine_not_started",
                        stress_cycle
                    );

                    total_mismatches =
                        total_mismatches + 1;
                end

                check_current_decision(
                    stress_cycle
                );

                check_cache_all(
                    stress_cycle
                );

                busy = 1;
                busy_cycles = 0;
            end

            guard();
        end

        access_valid = 1'b0;

        if (busy != 0) begin

            $display(
                "H4_STRESS_MISMATCH=reason:final_engine_still_busy"
            );

            total_mismatches =
                total_mismatches + 1;
        end
    end

    compare_full_q(
        999999
    );

    check_cache_all(
        999999
    );

    $display(
        "H4_REPLAY_VECTOR_COUNT=%0d",
        vector_count
    );

    $display(
        "H4_REPLAY_EXTERNAL_MISMATCH_COUNT=%0d",
        replay_external_mismatches
    );

    $display(
        "H4_REPLAY_Q_MISMATCH_COUNT=%0d",
        replay_q_mismatches
    );

    $display(
        "H4_REPLAY_CACHE_MISMATCH_COUNT=%0d",
        replay_cache_mismatches
    );

    $display(
        "H4_REPLAY_EXPECTED_MISMATCH_COUNT=%0d",
        replay_expected_mismatches
    );

    $display(
        "H4_ACTION4_DEGREE0_COVERAGE_COUNT=%0d",
        action4_degree0_count
    );

    $display(
        "H4_REPLAY_MAX_UPDATE_LATENCY=%0d",
        replay_max_latency
    );

    $display(
        "H4_STRESS_BOUNDARY_COUNT=%0d",
        stress_boundaries
    );

    $display(
        "H4_STRESS_EXTERNAL_MISMATCH_COUNT=%0d",
        stress_external_mismatches
    );

    $display(
        "H4_STRESS_Q_MISMATCH_COUNT=%0d",
        stress_q_mismatches
    );

    $display(
        "H4_STRESS_CACHE_MISMATCH_COUNT=%0d",
        stress_cache_mismatches
    );

    $display(
        "H4_STRESS_MAX_UPDATE_LATENCY=%0d",
        stress_max_latency
    );

    $display(
        "H4_TOTAL_MISMATCH_COUNT=%0d",
        total_mismatches
    );

    if (vector_count != 256) begin
        $display(
            "H4_FAIL=VECTOR_COUNT"
        );
        $finish;
    end

    if (action4_degree0_count <= 0) begin
        $display(
            "H4_FAIL=ACTION4_DEGREE0_NOT_EXERCISED"
        );
        $finish;
    end

    if (replay_max_latency > 128) begin
        $display(
            "H4_FAIL=REPLAY_LATENCY_BOUND"
        );
        $finish;
    end

    if (stress_max_latency > 128) begin
        $display(
            "H4_FAIL=STRESS_LATENCY_BOUND"
        );
        $finish;
    end

    if (stress_boundaries != 8) begin
        $display(
            "H4_FAIL=STRESS_BOUNDARY_COUNT"
        );
        $finish;
    end

    if (total_mismatches != 0) begin
        $display(
            "H4_FAIL=MISMATCHES"
        );
        $finish;
    end

    $display(
        "H4_EXTERNAL_TRAJECTORY_EQUIVALENCE=PASS"
    );

    $display(
        "H4_DEFERRED_Q_BIT_EXACT_EQUIVALENCE=PASS"
    );

    $display(
        "H4_CACHED_ARGMAX_EQUIVALENCE=PASS"
    );

    $display(
        "H4_ACTION4_DEGREE0_RUNTIME_COVERAGE=PASS"
    );

    $display(
        "H4_UPDATE_LATENCY_BOUND=PASS"
    );

    $display(
        "H4_CONTINUOUS_ACCESS_STRESS=PASS"
    );

    $display(
        "H4_BIT_EXACT_DEFERRED_EQUIVALENCE=PASS"
    );

    $finish;
end

endmodule
