// Properties of the ready controller, checked on every metaclock edge, with
// Phi1, Phi2 and every input free to change on any edge.
//
// The model follows the documented behavior, phase by phase:
//
// - During Phi2, the controller notes whether the next cycle writes (a store,
//   a PC push, BRK T4, a push at T2, or T6/T7 of a read-modify-write).
// - WR is that note while ready, except during reset.
// - During Phi1, the R/W pin takes WR, inverted, and the ready latch notes
//   whether this cycle writes.
// - During Phi2, ready is the RDY pin, or set anyway if this cycle writes.
// - ReadyPhi1 is ready from Phi1, during Phi2. PRDY is RDY from Phi2, during
//   Phi1.
//
// On top of the model, two properties the rest of the CPU relies on hold on
// every step: a cycle that isn't ready never writes, and a reset never
// writes, which turns the BRK sequence's pushes into reads.
//
// Everything powers up ready and not writing.
module ready_controller_formal (
    input metaclock,
    input phi1,
    input phi2,
    input rdy,
    input stor,
    input pc_db,
    input x98,
    input x100,
    input t6,
    input t7,
    input dores
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

    reg f_writes = 1'b0;
    reg f_writes_phi1 = 1'b0;
    reg f_ready = 1'b1;
    reg f_r_not_w = 1'b1;
    reg f_ready_phi1_in = 1'b1;
    reg f_ready_phi1 = 1'b1;
    reg f_rdy_phi2 = 1'b1;
    reg f_prdy = 1'b1;

    wire f_wr = f_ready && f_writes && !dores;

    always @(posedge metaclock) begin
        if (phi1) begin
            f_r_not_w <= !f_wr;
            f_writes_phi1 <= f_wr;
            f_ready_phi1_in <= f_ready;
            f_prdy <= f_rdy_phi2;
        end
        if (phi2) begin
            f_writes <= stor || pc_db || x98 || x100 || t6 || t7;
            f_ready <= rdy || f_writes_phi1;
            f_ready_phi1 <= f_ready_phi1_in;
            f_rdy_phi2 <= rdy;
        end
    end

    always @* begin
        check_ready: assert (ready == f_ready);
        check_wr: assert (wr == f_wr);
        check_r_not_w: assert (r_not_w == f_r_not_w);
        check_ready_phi1: assert (ready_phi1 == f_ready_phi1);
        check_prdy: assert (prdy == f_prdy);

        check_stall_never_writes: assert (!wr || ready);
        check_reset_never_writes: assert (!dores || !wr);
    end

    reg f_past_valid = 1'b0;
    always @(posedge metaclock) f_past_valid <= 1'b1;

    always @(posedge metaclock) begin
        if (f_past_valid) begin
            // RDY is low, but this cycle writes, so the CPU stays ready
            reach_write_ignores_rdy: cover ($past(phi2) && !$past(rdy) && ready && !r_not_w);
            reach_stall: cover ($past(phi2) && !$past(rdy) && !ready);
            // This cycle would write, but a reset makes it read instead
            reach_reset_read: cover ($past(phi1) && $past(dores) && $past(f_writes)
                && $past(ready) && r_not_w);
            reach_prdy_low: cover (!prdy && ready);
        end
    end
endmodule
