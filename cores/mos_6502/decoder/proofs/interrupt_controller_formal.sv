// Properties of the interrupt controller, phase by phase, with real
// Phi1/Phi2 clocks (two_phase_clock.sv).
//
// The harness keeps no model of the controller's latches. Each property
// relates an output at the end of a phase to that phase's inputs and to the
// outputs at the end of the phases before, as the controller's
// documentation describes them. Two of the states it describes aren't
// outputs, so the harness follows them as the documentation defines them:
// BRK cycle 6 (from 0/ADL0, which marks BRK T5 while ready), and whether an
// NMI edge is pending (DONMI, from the /NMI pin): from the edge until BRK6E.
// An edge during the vector cycles is taken after them: it's pending from the
// first Phi1 after a Phi2 that isn't a vector cycle.
//
// - Reset: RESP is /RES from Phi2, latched during Phi1. RESP sets DORES,
//   which holds until BRK6E.
// - BRK cycles: line 22 (BRK T5) while ready starts cycle 6, which holds
//   while not ready. BRK6E is cycle 6 while ready, from Phi2 of cycle 6
//   through Phi1 of cycle 7.
// - Vector: during the vector cycles (T5 while ready, then cycle 6), 0/ADL0
//   during T5, 0/ADL1 during a reset, and 0/ADL2 only for a pending NMI
//   outside a reset. So the vector is 0xFFFE, 0xFFFC or 0xFFFA.
// - B flag: a reset clears B_OUT. Otherwise it only goes low during T0 or
//   branch T2 (line 80), for a pending NMI or for /IRQ (from the Phi2
//   before) while I is clear, and an IRQ like that always clears it. It
//   stays low until BRK6E, which sets it again.
// - BRK6E only happens while ready.
//
// Every latched output holds while its phase is low. Each input changes
// only as a phase starts. Everything powers up idle, as if /RES, /NMI and
// /IRQ had been high.
//
// What the controller does for whole instruction sequences (an NMI taken
// after its vector cycles, bounded latency) is checked in decoder_formal.sv.
module interrupt_controller_formal (
    input metaclock,
    input end_phase,
    input nmi_n,
    input irq_n,
    input res_n,
    input ready,
    input x22,
    input x80,
    input t0,
    input i_flag
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

    wire resp, dores, brk6e, b_out, adl0, adl1, adl2;

    interrupt_controller dut (
        .phi1(phi1),
        .phi2(phi2),
        .nmi_pin_n_NMI(nmi_n),
        .irq_pin_n_IRQ(irq_n),
        .reset_pin_n_RES(res_n),
        .ready(ready),
        .brk_t5_X22(x22),
        .branch_t2_X80(x80),
        .cycle_T0(t0),
        .interrupt_disable_I_OUT(i_flag),
        .reset_pending_RESP(resp),
        .resetting_DORES(dores),
        .brk_cycle_6_end_BRK6E(brk6e),
        .break_flag_B_OUT(b_out),
        .clear_0_ADL0(adl0),
        .clear_0_ADL1(adl1),
        .clear_0_ADL2(adl2),
        .metaclock(metaclock)
    );


    // Each input only changes as a phase starts
    reg f_past_valid = 1'b0;
    reg [7:0] f_inputs_was = 8'b0;
    wire [7:0] f_inputs = {nmi_n, irq_n, res_n, ready, x22, x80, t0, i_flag};
    always @(posedge metaclock) begin
        f_past_valid <= 1'b1;
        f_inputs_was <= f_inputs;
    end
    always @* begin
        if (f_past_valid && !first_edge) begin
            assume_inputs_hold: assume (f_inputs == f_inputs_was);
        end
    end

    // The outputs and pins at the end of the last Phi1 and the last Phi2
    reg f_resp_phi1 = 1'b0;
    reg f_dores_phi1 = 1'b0;
    reg f_brk6e_phi1 = 1'b0;
    reg f_b_out_phi1 = 1'b1;
    reg f_dores_phi2 = 1'b0;
    reg f_b_out_phi2 = 1'b1;
    reg [2:0] f_vector_phi2 = 3'b0;
    reg f_res_low_phi2 = 1'b0;
    reg f_irq_low_phi2 = 1'b0;
    reg f_nmi_low_phi2 = 1'b0;
    // BRK cycle 6: the cycle after T5 while ready, held while not ready
    reg f_cycle6 = 1'b0;
    reg f_cycle6_was = 1'b0;
    // An NMI edge (/NMI high at the end of one Phi2, low at the end of a
    // later one) that BRK6E hasn't ended yet, and one that came during the
    // vector cycles, which is pending once they end
    reg f_nmi_pending = 1'b0;
    reg f_nmi_late = 1'b0;
    reg f_vector_cycle_phi2 = 1'b0;

    // The vector cycles: T5 while ready, then cycle 6
    wire f_t5_ready = x22 && ready;
    wire f_vector_cycle = f_t5_ready || f_cycle6;
    wire [2:0] f_vector = {adl2, adl1, adl0};
    wire f_nmi_edge = phi2 && last_edge && !nmi_n && !f_nmi_low_phi2;
    // The NMI vector starts: 0/ADL2 rises at the end of a Phi2
    wire f_nmi_vector = phi2 && last_edge && adl2 && !f_vector_phi2[2];

    always @(posedge metaclock) begin
        if (phi1 && last_edge) begin
            f_resp_phi1 <= resp;
            f_dores_phi1 <= dores;
            f_brk6e_phi1 <= brk6e;
            f_b_out_phi1 <= b_out;
            f_cycle6_was <= f_cycle6;
            f_cycle6 <= f_vector_phi2[0] || (f_cycle6 && !ready);
        end
        if (phi2 && last_edge) begin
            f_dores_phi2 <= dores;
            f_b_out_phi2 <= b_out;
            f_vector_phi2 <= f_vector;
            f_res_low_phi2 <= !res_n;
            f_irq_low_phi2 <= !irq_n;
            f_nmi_low_phi2 <= !nmi_n;
        end
        if (phi2 && last_edge) begin
            f_vector_cycle_phi2 <= f_vector_cycle;
            if (f_nmi_edge && f_vector_cycle) f_nmi_late <= 1'b1;
            else if (f_nmi_edge) f_nmi_pending <= 1'b1;
        end
        if (phi1 && last_edge) begin
            f_nmi_pending <= (f_nmi_pending && !brk6e)
                || (f_nmi_late && !f_vector_cycle_phi2);
            if (!f_vector_cycle_phi2) f_nmi_late <= 1'b0;
        end
    end

    // An interrupt check happens during T0 or branch T2
    wire f_check = t0 || x80;

    always @* begin
        if (phi1 && last_edge) begin
            check_resp: assert (resp == f_res_low_phi2);
            check_dores_phi1: assert (dores == (f_resp_phi1 || (f_dores_phi2 && !brk6e)));
            // BRK6E through Phi1 of cycle 7, while ready (f_cycle6 is still
            // the last cycle's, until this edge)
            check_brk6e_phi1: assert (brk6e == (f_cycle6 && ready));
        end
        if (phi2 && last_edge) begin
            check_dores_phi2: assert (dores == (resp || (f_dores_phi2 && !f_brk6e_phi1)));
            check_brk6e_phi2: assert (brk6e == (f_cycle6 && ready));
            check_adl0: assert (adl0 == f_t5_ready);
            check_adl1: assert (adl1 == (f_vector_cycle && dores));
            if (adl2) begin
                check_adl2_vector_cycle: assert (f_vector_cycle && !dores);
            end
            // It starts (it stays on through both vector cycles) only for a
            // pending NMI
            if (f_nmi_vector) begin
                check_adl2_cause: assert (f_nmi_pending || f_nmi_edge);
            end
            // B_OUT only goes low at an interrupt check, for an NMI or an
            // unmasked IRQ
            if (f_b_out_phi1 && !b_out && !dores) begin
                check_b_out_cause: assert (f_check
                    && (f_nmi_pending || f_nmi_edge || (f_irq_low_phi2 && !i_flag)));
            end
            // An unmasked IRQ at a check always clears it
            if (f_check && f_irq_low_phi2 && !i_flag && !brk6e) begin
                check_irq_clears_b_out: assert (!b_out);
            end
        end
        if (f_past_valid && last_edge) begin
            // Once low, B_OUT stays low until BRK6E, outside a reset
            if ((phi1 ? !f_b_out_phi2 : !f_b_out_phi1) && !brk6e && !dores
                    && !(phi1 ? f_dores_phi2 : f_dores_phi1)) begin
                check_b_out_holds: assert (!b_out);
            end
        end

        // Each latched output holds while its phase is low
        if (phi1) begin
            check_vector_holds_phi1: assert (f_vector == f_vector_phi2);
        end
        if (phi2) begin
            check_resp_holds_phi2: assert (resp == f_resp_phi1);
        end

        check_vector: assert (!(adl1 && adl2));
        check_reset_clears_b: assert (!dores || !b_out);
        check_brk6e_sets_b: assert (!brk6e || b_out == !dores);
        check_brk6e_ready: assert (!brk6e || ready);
    end

    always @* begin
        if (phi2 && last_edge) begin
            reach_nmi_vector: cover (adl2 && !adl1 && adl0);
            reach_reset_vector: cover (adl1 && !adl2 && adl0);
            reach_irq_vector: cover (adl0 && !adl1 && !adl2 && !b_out);
            reach_brk6e: cover (brk6e && !dores);
            reach_irq_masked: cover (f_check && f_irq_low_phi2 && i_flag && b_out);
            // Cycle 6 held while the CPU isn't ready
            reach_cycle6_stall: cover (f_cycle6 && f_cycle6_was && !ready);
            // An NMI takes over the vector of a BRK sequence already running
            reach_nmi_takes_over: cover (adl2 && x22 && b_out);
        end
    end
endmodule
