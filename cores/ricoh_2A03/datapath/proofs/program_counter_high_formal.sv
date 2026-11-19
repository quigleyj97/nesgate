// Properties of the program counter high byte, phase by phase, with real
// Phi1/Phi2 clocks (two_phase_clock.sv): the select register (PCHS), the
// increment logic, and PCH. Like program_counter_low_formal.sv, the harness
// follows PCHS and PCH as their documentation defines them, a phase at a
// time:
//
// - During Phi1, PCHS takes PCH (PCH/PCH) or ADH (ADH/PCH), and holds while
//   neither is selected. It holds through Phi2.
// - During Phi2, PCH takes PCHS + PCLC. It holds through Phi1.
// - PCH/DB and PCH/ADH drive PCH, and a disabled port drives all ones,
//   releasing the bus.
//
// The increment logic is split into two nibbles in the design. The property
// is a plain 8-bit increment by PCLC, so the proof shows that the nibbles
// carry into each other correctly, and that PCH wraps from 0xFF to 0x00.
//
// The random logic selects PCHS's source only outside Phi2, and never both
// sources at once, so the harness assumes the same. Each input changes only
// as a phase starts. Everything powers up as 0.
module program_counter_high_formal (
    input metaclock,
    input end_phase,
    input pch_pch,
    input adh_pch,
    input pclc,
    input pch_db,
    input pch_adh,
    input [7:0] adh_in
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

    wire [7:0] adh_out;
    wire [7:0] db_out;

    program_counter_high dut (
        .phi2(phi2),
        .signal_PCH_DB(pch_db),
        .signal_PCH_ADH(pch_adh),
        .signal_PCLC(pclc),
        .signal_PCH_PCH(pch_pch),
        .signal_ADH_PCH(adh_pch),
        .bus_ADH_in(adh_in),
        .bus_ADH_out(adh_out),
        .bus_DB(db_out),
        .metaclock(metaclock)
    );

    // Each input only changes as a phase starts
    wire [12:0] f_inputs = {pch_pch, adh_pch, pclc, pch_db, pch_adh, adh_in};
    reg f_past_valid = 1'b0;
    reg [12:0] f_inputs_was = 13'b0;
    always @(posedge metaclock) begin
        f_past_valid <= 1'b1;
        f_inputs_was <= f_inputs;
    end
    always @* begin
        if (f_past_valid && !first_edge) begin
            assume_inputs_hold: assume (f_inputs == f_inputs_was);
        end
        assume_one_source: assume (!(pch_pch && adh_pch));
        if (phi2) begin
            assume_no_select_phi2: assume (!pch_pch && !adh_pch);
        end
    end

    // PCHS at the end of the last Phi1, and PCH at the end of the last Phi2
    reg [7:0] f_pchs = 8'b0;
    reg [7:0] f_pch = 8'b0;
    wire [7:0] f_pchs_next = pch_pch ? f_pch : adh_pch ? adh_in : f_pchs;
    wire [7:0] f_incremented = f_pchs + {7'b0, pclc};
    always @(posedge metaclock) begin
        if (phi1 && last_edge) f_pchs <= f_pchs_next;
        if (phi2 && last_edge) f_pch <= f_incremented;
    end

    function [7:0] when_enabled(input enable, input [7:0] value);
        when_enabled = enable ? value : 8'hff;
    endfunction

    always @* begin
        // PCH holds through Phi1
        if (phi1) begin
            check_db_phi1: assert (db_out == when_enabled(pch_db, f_pch));
            check_adh_phi1: assert (adh_out == when_enabled(pch_adh, f_pch));
        end
        // The end of Phi2: PCH is PCHS + PCLC
        if (phi2 && last_edge) begin
            check_db_phi2: assert (db_out == when_enabled(pch_db, f_incremented));
            check_adh_phi2: assert (adh_out == when_enabled(pch_adh, f_incremented));
        end
    end

    always @* begin
        if (phi2 && last_edge) begin
            // The low nibble carries into the high nibble
            reach_nibble_carry: cover (pch_db && db_out == 8'h30 && f_pch == 8'h2f);
            reach_wrap: cover (pch_adh && adh_out == 8'h00 && f_pch == 8'hff);
            // A jump: ADH into PCHS, then into PCH
            reach_jump: cover (pch_db && db_out != 8'h00 && db_out != 8'hff
                && db_out != f_pch && db_out != f_pch + 8'd1);
        end
        if (phi1 && last_edge) begin
            reach_hold: cover (!pch_pch && !adh_pch && f_pchs != f_pch
                && f_pchs != 8'h00);
        end
    end
endmodule
