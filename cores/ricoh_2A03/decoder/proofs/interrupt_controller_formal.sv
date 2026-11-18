// Properties of the interrupt controller, checked on every metaclock edge,
// with Phi1, Phi2 and every input free to change on any edge.
//
// The harness keeps a model of the controller's latches, from its
// documentation, and checks every output against it. On top of the model:
//
// - The vector lines only ever select 0xFFFA (NMI), 0xFFFC (reset) or 0xFFFE
//   (IRQ/BRK): 0/ADL1 and 0/ADL2 are never set at once.
// - A reset clears B_OUT, so the BRK sequence pushes P with B clear.
// - BRK6E only ends the sequence while the CPU is ready.
//
// That NMI is edge-triggered is checked in decoder_formal.sv instead, since
// it only holds with real, non-overlapping clocks.
//
// Everything powers up idle.
module interrupt_controller_formal (
    input metaclock,
    input phi1,
    input phi2,
    input nmi_n,
    input irq_n,
    input res_n,
    input ready,
    input x22,
    input x80,
    input t0,
    input i_flag
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

    // Pad latches: the pins, active-high, during Phi2, and IRQ/RES again
    // during Phi1
    reg f_nmip = 1'b0;
    reg f_irq_phi2 = 1'b0, f_irqp = 1'b0;
    reg f_res_phi2 = 1'b0, f_resp = 1'b0;
    // BRK cycles 6-7
    reg f_brk5 = 1'b0, f_brk6 = 1'b0, f_brk6_phi2 = 1'b0;
    // Reset flip-flop
    reg f_res_set = 1'b0, f_res_hold = 1'b0;
    // NMI edge detector
    reg f_nmip_phi1 = 1'b0;
    reg f_nmi_was_high = 1'b1;
    reg f_in_vector = 1'b0;
    reg f_nmi_edge = 1'b0;
    reg f_donmi_phi2 = 1'b0;
    reg f_donmi_seen = 1'b0;
    reg f_brk6e_phi1 = 1'b0;
    // B flag
    reg f_no_interrupt = 1'b1, f_sequence_phi1 = 1'b0;
    // Vector
    reg f_adl0 = 1'b0, f_adl1 = 1'b0, f_adl2 = 1'b0;

    wire f_brk5_ready = x22 && ready;
    wire f_brk6e = f_brk6_phi2 && ready;
    wire f_vector_cycle = f_brk5_ready || f_brk6;
    wire f_dores = f_res_set || f_res_hold;
    wire f_donmi = f_nmi_edge || (f_donmi_phi2 && !f_brk6e_phi1);
    wire f_interrupt = (x80 || t0) && ((f_irqp && !i_flag) || f_donmi);
    wire f_sequence = !f_no_interrupt && !f_brk6e;

    always @(posedge metaclock) begin
        if (phi1) begin
            f_irqp <= f_irq_phi2;
            f_resp <= f_res_phi2;
            f_brk6 <= f_brk5 || (f_brk6 && !ready);
            f_res_hold <= f_dores && !f_brk6e;
            f_nmip_phi1 <= f_nmip;
            f_nmi_edge <= !f_in_vector && f_nmip && (!f_nmip_phi1
                || (f_nmi_was_high && !f_donmi_seen));
            f_donmi_seen <= f_donmi_phi2;
            f_brk6e_phi1 <= f_brk6e;
            f_sequence_phi1 <= f_sequence;
        end
        if (phi2) begin
            f_nmip <= !nmi_n;
            f_irq_phi2 <= !irq_n;
            f_res_phi2 <= !res_n;
            f_brk5 <= f_brk5_ready;
            f_brk6_phi2 <= f_brk6;
            f_res_set <= f_resp;
            f_nmi_was_high <= !f_nmip_phi1 || (f_nmi_was_high && !f_donmi_seen);
            f_in_vector <= f_vector_cycle;
            f_donmi_phi2 <= f_donmi;
            f_no_interrupt <= !f_interrupt && !f_sequence_phi1;
            f_adl0 <= f_brk5_ready;
            f_adl1 <= f_vector_cycle && f_dores;
            f_adl2 <= f_vector_cycle && !f_dores && f_donmi;
        end
    end

    always @* begin
        check_resp: assert (resp == f_resp);
        check_dores: assert (dores == f_dores);
        check_brk6e: assert (brk6e == f_brk6e);
        check_b_out: assert (b_out == (!f_dores && !f_sequence));
        check_adl0: assert (adl0 == f_adl0);
        check_adl1: assert (adl1 == f_adl1);
        check_adl2: assert (adl2 == f_adl2);

        check_vector: assert (!(adl1 && adl2));
        check_reset_clears_b: assert (!dores || !b_out);
        check_brk6e_ready: assert (!brk6e || ready);
    end

    reg f_past_valid = 1'b0;
    always @(posedge metaclock) f_past_valid <= 1'b1;

    always @(posedge metaclock) begin
        if (f_past_valid) begin
            reach_nmi_vector: cover (adl2 && !adl1 && adl0);
            reach_reset_vector: cover (adl1 && !adl2 && adl0);
            reach_irq_vector: cover (adl0 && !adl1 && !adl2 && !b_out);
            reach_brk6e: cover (brk6e && !dores);
            // An NMI takes over the vector of a BRK sequence already running
            reach_nmi_takes_over: cover (adl2 && $past(x22) && $past(b_out));
        end
    end
endmodule
