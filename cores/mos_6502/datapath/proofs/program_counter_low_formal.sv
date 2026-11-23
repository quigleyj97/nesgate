// Properties of the program counter low byte, phase by phase, with real
// Phi1/Phi2 clocks (two_phase_clock.sv): the select register (PCLS), the
// increment logic, and PCL.
//
// The harness keeps no model of the netlist's registers. PCLS and PCL aren't
// outputs (PCL only shows through its bus ports), so the harness follows them
// as their documentation defines them, a phase at a time:
//
// - During Phi1, PCLS takes PCL (PCL/PCL) or ADL (ADL/PCL), and holds while
//   neither is selected. It holds through Phi2.
// - During Phi2, PCL takes PCLS + 1/PC. It holds through Phi1.
// - PCLC, the carry out of the increment, is set exactly when 1/PC is high
//   and PCLS is 0xFF.
// - PCL/DB and PCL/ADL drive PCL, and a disabled port drives all ones,
//   releasing the bus.
//
// The random logic selects PCLS's source only outside Phi2, and never both
// sources at once (they're complements on the real chip), so the harness
// assumes the same. Each input changes only as a phase starts. Everything
// powers up as 0.
module program_counter_low_formal (
    input metaclock,
    input end_phase,
    input pcl_pcl,
    input adl_pcl,
    input i_pc,
    input pcl_db,
    input pcl_adl,
    input [7:0] adl_in
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

    wire pclc;
    wire [7:0] adl_out;
    wire [7:0] db_out;

    program_counter_low dut (
        .phi2(phi2),
        .signal_PCL_DB(pcl_db),
        .signal_PCL_ADL(pcl_adl),
        .signal_1_PC(i_pc),
        .signal_PCL_PCL(pcl_pcl),
        .signal_ADL_PCL(adl_pcl),
        .signal_PCLC(pclc),
        .bus_ADL_in(adl_in),
        .bus_ADL_out(adl_out),
        .bus_DB(db_out),
        .metaclock(metaclock)
    );

    // Each input only changes as a phase starts
    wire [12:0] f_inputs = {pcl_pcl, adl_pcl, i_pc, pcl_db, pcl_adl, adl_in};
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
        assume_one_source: assume (!(pcl_pcl && adl_pcl));
        if (phi2) begin
            assume_no_select_phi2: assume (!pcl_pcl && !adl_pcl);
        end
    end

    // PCLS at the end of the last Phi1, and PCL at the end of the last Phi2
    reg [7:0] f_pcls = 8'b0;
    reg [7:0] f_pcl = 8'b0;
    wire [7:0] f_pcls_next = pcl_pcl ? f_pcl : adl_pcl ? adl_in : f_pcls;
    // PCLS + 1/PC, with its carry out
    wire [8:0] f_incremented = {1'b0, f_pcls} + {8'b0, i_pc};
    always @(posedge metaclock) begin
        if (phi1 && last_edge) f_pcls <= f_pcls_next;
        if (phi2 && last_edge) f_pcl <= f_incremented[7:0];
    end

    function [7:0] when_enabled(input enable, input [7:0] value);
        when_enabled = enable ? value : 8'hff;
    endfunction

    always @* begin
        // PCL holds through Phi1
        if (phi1) begin
            check_db_phi1: assert (db_out == when_enabled(pcl_db, f_pcl));
            check_adl_phi1: assert (adl_out == when_enabled(pcl_adl, f_pcl));
        end
        // PCLS holds through Phi2, so PCLC does too
        if (phi2) begin
            check_pclc: assert (pclc == f_incremented[8]);
        end
        // The end of Phi2: PCL is PCLS + 1/PC
        if (phi2 && last_edge) begin
            check_db_phi2: assert (db_out == when_enabled(pcl_db, f_incremented[7:0]));
            check_adl_phi2: assert (adl_out == when_enabled(pcl_adl, f_incremented[7:0]));
        end
    end

    always @* begin
        if (phi2 && last_edge) begin
            // PCL increments through PCLS, wrapping from 0xFF with a carry
            reach_wrap: cover (pcl_adl && adl_out == 8'h00 && f_pcl == 8'hff
                && f_pcls == 8'hff && pclc);
            // A jump: ADL into PCLS, then into PCL without incrementing
            reach_jump: cover (pcl_db && !i_pc && db_out != 8'h00
                && db_out != 8'hff && db_out != f_pcl + 8'd1 && db_out != f_pcl);
        end
        if (phi1 && last_edge) begin
            // PCLS holds with neither source selected, while PCL differs
            reach_hold: cover (!pcl_pcl && !adl_pcl && f_pcls != f_pcl
                && f_pcls != 8'h00);
        end
    end
endmodule
