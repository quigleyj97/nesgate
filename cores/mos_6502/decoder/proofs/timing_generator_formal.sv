// Properties of the timing generator, cycle by cycle, with real Phi1/Phi2
// clocks (two_phase_clock.sv).
//
// The harness keeps no model of the generator's latches. Each property states
// how the outputs of one cycle follow from that cycle's inputs and the
// outputs of the cycle before, as the timing generator's documentation
// describes the three counters, so a property only depends on what the
// generator is meant to do, not on how its latches do it:
//
// - T1 is TRES1, and TRES2 is TRESX, both from Phi1.
// - T1X follows T0 one cycle later, while ready.
// - T0 is set outside T1 when the next instruction takes 2 cycles
//   (TWOCYCLE) or the current one is finishing (TRES2), and stays set until
//   T1X.
// - T2-T5 are a shift register that moves T1 on one stage per cycle while
//   ready, holds while not ready, and clears on TRES2.
// - T6 follows a cycle with SHIFT and MemOP set while ready, and holds while
//   not ready. T7 follows a cycle of T6 while ready.
//
// Every output comes from a Phi1 latch, so it's read at the end of Phi1, and
// holds still through Phi2. Each input changes only as a phase starts, and
// is used in the phase the documentation latches it in: TRES1, TRESX and
// TWOCYCLE in Phi1, SHIFT and MemOP in Phi2, and ready in both. Everything
// powers up clear, as if the cycle before power-on had every output and
// input low.
module timing_generator_formal (
    input metaclock,
    input end_phase,
    input ready,
    input tres1,
    input tresx,
    input twocycle,
    input shift,
    input memop
);
    wire phi1, phi2, first_edge, last_edge;
    two_phase_clock clock (
        .metaclock(metaclock),
        .end_phase(end_phase),
        .phi1(phi1),
        .phi2(phi2),
        .first_edge(first_edge),
        .last_edge(last_edge)
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

    wire [8:0] f_outputs = {t7, t6, t5, t4, t3, t2, t1x, t1, t0};
    wire [5:2] f_extended = {t5, t4, t3, t2};

    // Each input only changes as a phase starts
    reg f_past_valid = 1'b0;
    reg [5:0] f_inputs_was = 6'b0;
    wire [5:0] f_inputs = {ready, tres1, tresx, twocycle, shift, memop};
    always @(posedge metaclock) begin
        f_past_valid <= 1'b1;
        f_inputs_was <= f_inputs;
    end
    always @* begin
        if (f_past_valid && !first_edge) begin
            assume_inputs_hold: assume (f_inputs == f_inputs_was);
        end
    end

    // The outputs at the end of the last Phi1, and the inputs during the
    // last Phi2: the cycle before, once the current Phi1 is under way
    reg [8:0] f_outputs_cycle = 9'b0;
    reg f_shift_phi2 = 1'b0;
    reg f_memop_phi2 = 1'b0;
    reg f_ready_phi2 = 1'b0;
    always @(posedge metaclock) begin
        if (phi1 && last_edge) f_outputs_cycle <= f_outputs;
        if (phi2 && last_edge) begin
            f_shift_phi2 <= shift;
            f_memop_phi2 <= memop;
            f_ready_phi2 <= ready;
        end
    end
    wire f_t0_was = f_outputs_cycle[0];
    wire f_t1_was = f_outputs_cycle[1];
    wire f_t6_was = f_outputs_cycle[7];
    wire [5:2] f_extended_was = f_outputs_cycle[6:3];

    always @* begin
        // The end of Phi1: this cycle's outputs, from its inputs and the
        // cycle before
        if (phi1 && last_edge) begin
            check_t1: assert (t1 == tres1);
            check_t1x: assert (t1x == (f_t0_was && ready));
            check_t0: assert (t0 == ((!t1 && (twocycle || tresx)) || (f_t0_was && !t1x)));
            check_extended: assert (f_extended == (tresx ? 4'b0
                : ready ? {f_extended_was[4:2], f_t1_was} : f_extended_was));
            check_t6: assert (t6 == ((f_shift_phi2 && f_memop_phi2 && f_ready_phi2)
                || (f_t6_was && !ready)));
            check_t7: assert (t7 == (f_t6_was && f_ready_phi2));
        end
        // Every output holds through Phi2
        if (phi2) begin
            check_hold_phi2: assert (f_outputs == f_outputs_cycle);
        end
    end

    always @* begin
        if (phi1 && last_edge) begin
            reach_t5: cover (t5 && !t4 && !t3 && !t2);
            reach_t7: cover (t7 && !t6);
            // T0 and T2 at once, on a 2-cycle instruction
            reach_t0_t2: cover (t0 && t2);
            // The counter holds T3 while the CPU isn't ready
            reach_stall: cover (!ready && t3 && f_extended_was[3]);
            // TRES2 clears the extended counter
            reach_reset: cover (tresx && f_extended_was != 4'b0);
            // T0 stays set until T1X
            reach_t0_held: cover (t0 && f_t0_was && !t1x && !twocycle && !tresx);
        end
    end
endmodule
