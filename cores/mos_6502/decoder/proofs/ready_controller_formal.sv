// Properties of the ready controller, phase by phase, with real Phi1/Phi2
// clocks (two_phase_clock.sv).
//
// The harness keeps no model of the controller's latches. Each property
// relates an output at the end of a phase to that phase's inputs and to the
// outputs at the end of the phase before, as the controller's documentation
// describes them:
//
// - The write latch (Phi2) is set when the next cycle writes: STOR, PC/DB,
//   BRK T4 (line 98), a push at T2 (line 100), T6 or T7. WR is the write
//   latch while ready, except during a reset (DORES).
// - The R/W pin holds WR, inverted, from Phi1 for the whole cycle.
// - ready (Phi2) is RDY, or WR from the last Phi1, so a write cycle never
//   stalls, and holds through Phi1.
// - ReadyPhi1 is ready from Phi1, held through Phi2. PRDY is RDY from Phi2,
//   then Phi1.
//
// On top of that, on every step, the CPU only writes while ready, and never
// during a reset. Each input changes only as a phase starts. Everything
// powers up ready and not writing, as if the cycle before power-on had RDY
// high and nothing to write.
module ready_controller_formal (
    input metaclock,
    input end_phase,
    input rdy,
    input stor,
    input pc_db,
    input x98,
    input x100,
    input t6,
    input t7,
    input dores
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

    wire ready, wr, r_not_w, ready_phi1, prdy;

    ready_controller dut (
        .phi1(phi1),
        .phi2(phi2),
        .ready_pin_RDY(rdy),
        .store_cycle_STOR(stor),
        .pc_to_db_PC_DB(pc_db),
        .brk_t4_X98(x98),
        .push_t2_X100(x100),
        .rmw_cycle_T6(t6),
        .rmw_cycle_T7(t7),
        .resetting_DORES(dores),
        .ready(ready),
        .write_cycle_WR(wr),
        .read_not_write_R_NOT_W(r_not_w),
        .ready_phi1_ReadyPhi1(ready_phi1),
        .previous_ready_PRDY(prdy),
        .metaclock(metaclock)
    );

    // The next cycle writes to memory, from the decoder
    wire f_writes = stor || pc_db || x98 || x100 || t6 || t7;

    // Each input only changes as a phase starts
    reg f_past_valid = 1'b0;
    reg [7:0] f_inputs_was = 8'b0;
    wire [7:0] f_inputs = {rdy, stor, pc_db, x98, x100, t6, t7, dores};
    always @(posedge metaclock) begin
        f_past_valid <= 1'b1;
        f_inputs_was <= f_inputs;
    end
    always @* begin
        if (f_past_valid && !first_edge) begin
            assume_inputs_hold: assume (f_inputs == f_inputs_was);
        end
    end

    // The outputs and inputs at the end of the last Phi1 and the last Phi2
    reg f_wr_phi1 = 1'b0;
    reg f_ready_phi1 = 1'b1;
    reg f_r_not_w_phi1 = 1'b1;
    reg f_prdy_phi1 = 1'b1;
    reg f_ready_phi2 = 1'b1;
    reg f_ready_phi1_phi2 = 1'b1;
    reg f_rdy_phi2 = 1'b1;
    reg f_writes_phi2 = 1'b0;
    always @(posedge metaclock) begin
        if (phi1 && last_edge) begin
            f_wr_phi1 <= wr;
            f_ready_phi1 <= ready;
            f_r_not_w_phi1 <= r_not_w;
            f_prdy_phi1 <= prdy;
        end
        if (phi2 && last_edge) begin
            f_ready_phi2 <= ready;
            f_ready_phi1_phi2 <= ready_phi1;
            f_rdy_phi2 <= rdy;
            f_writes_phi2 <= f_writes;
        end
    end

    always @* begin
        if (phi1 && last_edge) begin
            check_wr_phi1: assert (wr == (ready && f_writes_phi2 && !dores));
            check_r_not_w: assert (r_not_w == !wr);
            check_prdy: assert (prdy == f_rdy_phi2);
        end
        if (phi2 && last_edge) begin
            check_ready: assert (ready == (rdy || f_wr_phi1));
            check_ready_phi1: assert (ready_phi1 == f_ready_phi1);
            check_wr_phi2: assert (wr == (ready && f_writes && !dores));
            // The cycle that writes doesn't stall
            if (!r_not_w) begin
                check_write_never_stalls: assert (ready);
            end
        end
        // Each latch holds while its phase is low
        if (phi1) begin
            check_ready_holds_phi1: assert (ready == f_ready_phi2);
            check_ready_phi1_holds_phi1: assert (ready_phi1 == f_ready_phi1_phi2);
        end
        if (phi2) begin
            check_r_not_w_holds_phi2: assert (r_not_w == f_r_not_w_phi1);
            check_prdy_holds_phi2: assert (prdy == f_prdy_phi1);
        end

        check_stall_never_writes: assert (!wr || ready);
        check_reset_never_writes: assert (!dores || !wr);
    end

    always @* begin
        if (phi2 && last_edge) begin
            // RDY is low, but this cycle writes, so the CPU stays ready
            reach_write_ignores_rdy: cover (!rdy && ready && !r_not_w);
            reach_stall: cover (!rdy && !ready);
        end
        if (phi1 && last_edge) begin
            // This cycle would write, but a reset makes it read instead
            reach_reset_read: cover (dores && f_writes_phi2 && ready && r_not_w);
            reach_write: cover (!r_not_w);
            reach_prdy_low: cover (!prdy && ready);
        end
    end
endmodule
