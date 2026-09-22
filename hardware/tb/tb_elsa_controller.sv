`timescale 1ns/1ps

module tb_elsa_controller;

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

    task automatic fail(
        input string msg
    );
        begin
            $display(
                "SMOKE_FAIL=%s",
                msg
            );

            $finish(2);
        end
    endtask

    task automatic one_access(
        input logic [63:0] addr
    );
        begin
            demand_addr =
                addr;

            access_valid =
                1'b1;

            @(posedge clk);
            #1;

            access_valid =
                1'b0;
        end
    endtask

    integer i;

    initial begin

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

        if (current_state !== 3'd0)
            fail(
                "reset state is not 0"
            );

        if (current_action !== 2'd1)
            fail(
                "reset action is not index 1"
            );

        if (current_degree !== 4'd8)
            fail(
                "reset degree is not 8"
            );

        if (capped_degree !== 4'd8)
            fail(
                "initial cap mismatch"
            );

        $display(
            "RESET_CONTRACT=PASS"
        );

        /*
         * First empty epoch.
         *
         * accuracy=0
         * old degree=8
         * next state=1
         *
         * all Q values are tied at zero,
         * therefore strict-greater greedy
         * selection must return action 0.
         */
        for (
            i = 0;
            i < 1024;
            i = i + 1
        )
            one_access(
                64'h0000_0000_0001_0000
                +
                i * 64
            );

        #1;

        if (current_state !== 3'd1)
            fail(
                "first epoch state should be 1"
            );

        if (current_action !== 2'd0)
            fail(
                "first epoch action should be 0"
            );

        if (current_degree !== 4'd1)
            fail(
                "first epoch degree should be 1"
            );

        if (capped_degree !== 4'd1)
            fail(
                "learned cap 1 not applied"
            );

        $display(
            "FIRST_EPOCH_GREEDY_TIE_CONTRACT=PASS"
        );

        /*
         * Second empty epoch.
         * Degree is now <=2, therefore
         * accuracy bucket 0 maps to state 0.
         */
        for (
            i = 0;
            i < 1024;
            i = i + 1
        )
            one_access(
                64'h0000_0000_0010_0000
                +
                i * 64
            );

        #1;

        if (current_state !== 3'd0)
            fail(
                "second epoch state should be 0"
            );

        if (current_action !== 2'd0)
            fail(
                "second epoch action should remain 0"
            );

        if (current_degree !== 4'd1)
            fail(
                "second epoch degree should remain 1"
            );

        $display(
            "SECOND_EPOCH_STATE_CONTRACT=PASS"
        );

        /*
         * Usefulness tracker smoke.
         */
        prefetch_addr =
            64'h0000_0000_1000_0000;

        prefetch_issue_valid =
            1'b1;

        @(posedge clk);
        #1;

        prefetch_issue_valid =
            1'b0;

        if (epoch_pref_issued !== 64'd1)
            fail(
                "prefetch issued counter mismatch"
            );

        one_access(
            64'h0000_0000_1000_0000
        );

        #1;

        if (epoch_pref_useful !== 64'd1)
            fail(
                "useful prefetch counter mismatch"
            );

        $display(
            "TRACKER_USEFULNESS_CONTRACT=PASS"
        );

        /*
         * RL disabled means the learned cap
         * must not restrict natural degree.
         */
        rl_enable =
            1'b0;

        natural_degree =
            4'd8;

        #1;

        if (capped_degree !== 4'd8)
            fail(
                "RL disable did not bypass cap"
            );

        $display(
            "RL_DISABLE_CAP_BYPASS=PASS"
        );

        $display(
            "ELSA_RTL_BASIC_SMOKE=PASS"
        );

        $finish(0);
    end

endmodule
