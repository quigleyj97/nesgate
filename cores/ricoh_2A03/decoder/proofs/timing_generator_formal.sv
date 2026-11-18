// Properties of the timing generator, checked on every metaclock edge, with
// Phi1, Phi2 and every input free to change on any edge (both phases can even
// be high at once).
//
// The model describes each counter by what its outputs do, rather than by
// its latches: during Phi2 the counters sample their own outputs, and during
// Phi1 they move on to the next cycle from those samples.
//
// - T1 is TRES1, latched during Phi1. TRES2 is TRESX, latched during Phi1.
// - The extended counter shifts T1-T4 (as they were during Phi2) into T2-T5
//   during Phi1 while ready, and keeps T2-T5 while not ready. TRES2 clears
//   T2-T5.
// - T0 is set outside T1 when the next instruction takes 2 cycles (TWOCYCLE
//   during Phi1) or TRES2 is set, and holds until T1X. T1X is T0 (during
//   Phi2) one cycle later, while ready.
// - T6 follows a cycle with SHIFT and MemOP (during Phi2, while ready), and
//   holds while not ready. T7 follows T6 while ready.
//
// Everything powers up clear.
module timing_generator_formal (
    input metaclock,
    input phi1,
    input phi2,
    input ready,
    input tres1,
    input tresx,
    input twocycle,
    input shift,
    input memop
);
    wire t0, t1, t1x, t2, t3, t4, t5, t6, t7;

    timing_generator dut (
        .phi1(phi1),
        .phi2(phi2),
        .ready(ready),
        .reset_short_counter_TRES1(tres1),
        .reset_counters_TRESX(tresx),
        .short_instruction_TWOCYCLE(twocycle),
        .shift_instruction_SHIFT(shift),
        .memory_operation_MemOP(memop),
        .cycle_T0(t0),
        .cycle_T1(t1),
        .cycle_T1X(t1x),
        .cycle_T2(t2),
        .cycle_T3(t3),
        .cycle_T4(t4),
        .cycle_T5(t5),
        .rmw_cycle_T6(t6),
        .rmw_cycle_T7(t7),
        .metaclock(metaclock)
    );

    wire [5:2] f_extended_out = {t5, t4, t3, t2};

    // Samples taken during Phi2
    reg [5:1] f_t1_t5_phi2 = 5'b0;
    reg f_t0_phi2 = 1'b0;
    reg f_t6_start_phi2 = 1'b0;
    reg f_t6_phi2 = 1'b0;
    reg f_t7_start_phi2 = 1'b0;
    // The cycle state, from Phi1
    reg f_t1 = 1'b0;
    reg f_tres2 = 1'b0;
    reg f_twocycle = 1'b0;
    reg f_t1x = 1'b0;
    reg [5:2] f_extended = 4'b0;
    reg f_t6 = 1'b0;
    reg f_t7 = 1'b0;

    always @(posedge metaclock) begin
        if (phi2) begin
            f_t1_t5_phi2 <= {f_extended_out, t1};
            f_t0_phi2 <= t0;
            f_t6_start_phi2 <= shift && memop && ready;
            f_t6_phi2 <= t6;
            f_t7_start_phi2 <= t6 && ready;
        end
        if (phi1) begin
            f_t1 <= tres1;
            f_tres2 <= tresx;
            f_twocycle <= twocycle;
            f_t1x <= f_t0_phi2 && ready;
            // Shift one stage per cycle, or hold the stages from Phi2
            f_extended <= ready ? f_t1_t5_phi2[4:1] : f_t1_t5_phi2[5:2];
            f_t6 <= f_t6_start_phi2 || (f_t6_phi2 && !ready);
            f_t7 <= f_t7_start_phi2;
        end
    end

    always @* begin
        check_t1: assert (t1 == f_t1);
        check_t1x: assert (t1x == f_t1x);
        check_t0: assert (t0 == ((!f_t1 && (f_twocycle || f_tres2))
            || (f_t0_phi2 && !f_t1x)));
        check_extended: assert (f_extended_out == (f_tres2 ? 4'b0 : f_extended));
        check_t6: assert (t6 == f_t6);
        check_t7: assert (t7 == f_t7);
    end

    reg f_past_valid = 1'b0;
    always @(posedge metaclock) f_past_valid <= 1'b1;

    always @* begin
        reach_t5: cover (t5 && !t4 && !t3 && !t2);
        reach_t7: cover (t7 && !t6);
        // T0 and T2 at once, on a 2-cycle instruction
        reach_t0_t2: cover (t0 && t2);
    end

    always @(posedge metaclock) begin
        if (f_past_valid) begin
            // The counter holds T3 through a Phi1 while the CPU isn't ready
            reach_stall: cover ($past(phi1) && !$past(phi2) && !$past(ready)
                && $past(t3) && t3 && !t4);
            // TRES2 clears the extended counter
            reach_reset: cover ($past(t4) && !t4 && !t5 && !t2 && !t3);
        end
    end
endmodule
