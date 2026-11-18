// Properties of the phased clock generator. Its input clock is an ordinary
// input here, under SymbiYosys's multiclock mode: every step is a tick of the
// global formal clock, and clk_in can rise or fall on any step, or stay put
// for any number of steps. So the proof also shows that the phases only
// change on a rising edge of clk_in, never on a falling one or between edges.
module phased_clock_generator_formal (
    input clk_in
);
    wire clk_out;
    wire clk_phi1;
    wire clk_phi2;

    phased_clock_generator dut (
        .clk_in(clk_in),
        .clk_out(clk_out),
        .clk_phi1(clk_phi1),
        .clk_phi2(clk_phi2)
    );

    reg f_past_valid = 1'b0;
    reg f_clk_was = 1'b0;
    reg f_phi2_was = 1'b0;
    // Phase changes so far, saturating at 3 (for the covers)
    reg [1:0] f_changes = 2'd0;

    wire f_rose = clk_in && !f_clk_was;
    wire f_fell = !clk_in && f_clk_was;
    wire f_changed = f_past_valid && clk_phi2 != f_phi2_was;

    always @($global_clock) begin
        f_past_valid <= 1'b1;
        f_clk_was <= clk_in;
        f_phi2_was <= clk_phi2;
        if (f_changed && f_changes != 2'd3) f_changes <= f_changes + 1'b1;
    end

    always @* begin
        if (!f_past_valid) begin
            assume_power_up: assume (!clk_in);
            check_power_up: assert (clk_phi1 && !clk_phi2);
        end

        // Exactly one phase is high at any time
        check_non_overlap: assert (!(clk_phi1 && clk_phi2));
        check_no_gap: assert (clk_phi1 || clk_phi2);
        check_clk_out: assert (clk_out == clk_phi2);

        // The phases swap on every rising edge of clk_in, and only then
        if (f_past_valid) begin
            check_swap: assert (f_changed == f_rose);
        end

        reach_phi1_to_phi2: cover (f_rose && clk_phi2);
        reach_phi2_to_phi1: cover (f_rose && clk_phi1);
        reach_falling_edge: cover (f_past_valid && f_fell && f_changes != 2'd0);
        // clk_in held high past a rising edge, a few phases in
        reach_slow_input: cover (f_past_valid && !f_rose && !f_fell
            && clk_in && f_changes == 2'd3);
    end
endmodule
