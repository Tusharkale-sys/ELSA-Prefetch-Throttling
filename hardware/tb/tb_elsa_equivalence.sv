`timescale 1ns/1ps

module tb_elsa_equivalence;

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

    logic [3:0] capped_degree;

    logic [2:0] current_state;
    logic [1:0] current_action;
    logic [3:0] current_degree;

    logic epoch_update_pulse;

    logic [63:0] epoch_pref_issued;
    logic [63:0] epoch_pref_useful;

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
    integer mismatch_count;

    integer j;

    string vector_path;

    logic [63:0] line_value;
    logic [63:0] addr_value;

    elsa_controller #(
        .EPOCH_LEN(1024),
        .Q_WIDTH(64),
        .Q_FRAC(24),
        .LINE_SHIFT(6)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),

        .rl_enable(rl_enable),

        .access_valid(access_valid),
        .demand_addr(demand_addr),

        .prefetch_issue_valid(
            prefetch_issue_valid
        ),

        .prefetch_addr(
            prefetch_addr
        ),

        .bw_update_valid(
            bw_update_valid
        ),

        .bw_level_in(
            bw_level_in
        ),

        .natural_degree(
            natural_degree
        ),

        .capped_degree(
            capped_degree
        ),

        .current_state(
            current_state
        ),

        .current_action(
            current_action
        ),

        .current_degree(
            current_degree
        ),

        .epoch_update_pulse(
            epoch_update_pulse
        ),

        .epoch_pref_issued(
            epoch_pref_issued
        ),

        .epoch_pref_useful(
            epoch_pref_useful
        )
    );

    initial
        clk = 1'b0;

    always
        #5 clk = ~clk;

    task automatic pulse_bw(
        input integer bw
    );
        begin
            bw_level_in =
                bw[7:0];

            bw_update_valid =
                1'b1;

            @(posedge clk);
            #1;

            bw_update_valid =
                1'b0;
        end
    endtask

    task automatic issue_line(
        input logic [63:0] line
    );
        begin
            prefetch_addr =
                line << 6;

            prefetch_issue_valid =
                1'b1;

            @(posedge clk);
            #1;

            prefetch_issue_valid =
                1'b0;
        end
    endtask

    task automatic access_line(
        input logic [63:0] line
    );
        begin
            demand_addr =
                line << 6;

            access_valid =
                1'b1;

            @(posedge clk);
            #1;

            access_valid =
                1'b0;
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
                "RTL_EQ_FAIL=VECTOR_PATH_MISSING"
            );

            $finish(2);
        end

        fd =
            $fopen(
                vector_path,
                "r"
            );

        if (fd == 0) begin
            $display(
                "RTL_EQ_FAIL=CANNOT_OPEN_VECTOR_FILE"
            );

            $finish(2);
        end

        rst_n = 1'b0;

        rl_enable = 1'b1;

        access_valid = 1'b0;
        demand_addr = 64'd0;

        prefetch_issue_valid = 1'b0;
        prefetch_addr = 64'd0;

        bw_update_valid = 1'b0;
        bw_level_in = 8'd0;

        natural_degree = 4'd8;

        vector_count = 0;
        mismatch_count = 0;

        repeat (3)
            @(posedge clk);

        rst_n = 1'b1;

        @(posedge clk);
        #1;

        while (
            !$feof(fd)
        ) begin

            rc =
                $fscanf(
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
                    "RTL_EQ_FAIL=VECTOR_PARSE epoch_index=%0d rc=%0d",
                    vector_count,
                    rc
                );

                $finish(3);
            end

            pulse_bw(
                bw_i
            );

            /*
             * Issue all prefetches before the counted accesses.
             * Lines 1..48 within each epoch use unique tracker
             * indices because the epoch base is a multiple of 128.
             */
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
                    line_value
                );
            end

            /*
             * Consume exactly useful_i of those lines.
             */
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
                    line_value
                );
            end

            /*
             * Fill the remainder to exactly 1024 L2 accesses.
             * Filler lines are disjoint from all prefetched lines.
             */
            for (
                j = useful_i;
                j < 1024;
                j = j + 1
            ) begin

                line_value =
                    64'h0000_0000_1000_0000
                    +
                    epoch_id * 2048
                    +
                    j;

                access_line(
                    line_value
                );
            end

            if (
                epoch_update_pulse
                !==
                1'b1
            ) begin
                $display(
                    "RTL_EQ_MISMATCH epoch=%0d field=epoch_update_pulse got=%b expected=1",
                    epoch_id,
                    epoch_update_pulse
                );

                mismatch_count =
                    mismatch_count + 1;
            end

            if (
                current_state
                !==
                exp_state_i[2:0]
            ) begin
                $display(
                    "RTL_EQ_MISMATCH epoch=%0d field=state got=%0d expected=%0d",
                    epoch_id,
                    current_state,
                    exp_state_i
                );

                mismatch_count =
                    mismatch_count + 1;
            end

            if (
                current_action
                !==
                exp_action_i[1:0]
            ) begin
                $display(
                    "RTL_EQ_MISMATCH epoch=%0d field=action got=%0d expected=%0d",
                    epoch_id,
                    current_action,
                    exp_action_i
                );

                mismatch_count =
                    mismatch_count + 1;
            end

            if (
                current_degree
                !==
                exp_degree_i[3:0]
            ) begin
                $display(
                    "RTL_EQ_MISMATCH epoch=%0d field=degree got=%0d expected=%0d",
                    epoch_id,
                    current_degree,
                    exp_degree_i
                );

                mismatch_count =
                    mismatch_count + 1;
            end

            if (
                dut.q_table
                    [upd_state_i]
                    [upd_action_i]
                !==
                exp_q_bits
            ) begin
                $display(
                    "RTL_EQ_MISMATCH epoch=%0d field=q_update state=%0d action=%0d got=%h expected=%h",
                    epoch_id,
                    upd_state_i,
                    upd_action_i,
                    dut.q_table
                        [upd_state_i]
                        [upd_action_i],
                    exp_q_bits
                );

                mismatch_count =
                    mismatch_count + 1;
            end

            vector_count =
                vector_count + 1;

            if (
                mismatch_count != 0
            ) begin
                $display(
                    "RTL_EQ_FAIL=FIRST_MISMATCH epoch=%0d mismatches=%0d",
                    epoch_id,
                    mismatch_count
                );

                $finish(4);
            end
        end

        $fclose(fd);

        $display(
            "RTL_EQ_VECTOR_COUNT=%0d",
            vector_count
        );

        $display(
            "RTL_EQ_MISMATCH_COUNT=%0d",
            mismatch_count
        );

        if (
            vector_count != 256
        ) begin
            $display(
                "RTL_EQ_FAIL=VECTOR_COUNT"
            );

            $finish(5);
        end

        if (
            mismatch_count != 0
        ) begin
            $display(
                "RTL_EQ_FAIL=MISMATCHES"
            );

            $finish(6);
        end

        $display(
            "RTL_FIXED_BIT_EXACT_TRAJECTORY_EQUIVALENCE=PASS"
        );

        $finish(0);
    end

endmodule
