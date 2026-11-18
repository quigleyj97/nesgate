// Properties of the program counter low byte: the select register (PCLS),
// the increment logic, and PCL.
//
// Both PCLS and PCL load on the metaclock: PCLS when PCL/PCL or ADL/PCL is
// high, and PCL while Phi2 is high. The proof runs with SymbiYosys's
// multiclock mode so that the metaclock is an ordinary input: every step is
// a tick of the global formal clock, and the metaclock, Phi2 and the control
// signals can change on any step, independently of each other. Each register in the
// model keeps the value it would take on its next edge, computed from the
// inputs on the step before, like the netlist's registers.
//
// A disabled bus port drives all ones, releasing the bus.
module program_counter_low_formal (
    input metaclock,
    input phi2,
    input pcl_pcl,
    input adl_pcl,
    input i_pc,
    input pcl_db,
    input pcl_adl,
    input [7:0] adl_in
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

    reg f_past_valid = 1'b0;
    reg f_metaclock_was = 1'b0;
    reg f_phi2_was = 1'b0;
    // Each register as it was on the step before, and what it would have
    // taken on an edge
    reg [7:0] f_select_was = 8'b0;
    reg [7:0] f_select_next_was = 8'b0;
    reg [7:0] f_pcl_was = 8'b0;
    reg [7:0] f_pcl_next_was = 8'b0;

    wire f_metaclock_rose = metaclock && !f_metaclock_was;
    // PCL loads on a metaclock edge if Phi2 was high just before it
    wire f_phi2_load = f_metaclock_rose && f_phi2_was;

    wire [7:0] f_select = f_metaclock_rose ? f_select_next_was : f_select_was;
    wire [7:0] f_pcl = f_metaclock_rose ? f_pcl_next_was : f_pcl_was;
    // PCLS takes PCL (PCL/PCL), or else ADL (ADL/PCL), or else holds
    wire [7:0] f_select_next = pcl_pcl ? f_pcl : adl_pcl ? adl_in : f_select;
    // The increment logic adds 1/PC, with the carry out as PCLC
    wire [8:0] f_incremented = {1'b0, f_select} + {8'b0, i_pc};

    always @($global_clock) begin
        f_past_valid <= 1'b1;
        f_metaclock_was <= metaclock;
        f_phi2_was <= phi2;
        f_select_was <= f_select;
        f_select_next_was <= f_select_next;
        f_pcl_was <= f_pcl;
        f_pcl_next_was <= phi2 ? f_incremented[7:0] : f_pcl;
    end

    always @* begin
        if (!f_past_valid) begin
            assume_power_up: assume (!metaclock && !phi2);
        end

        check_pclc: assert (pclc == f_incremented[8]);
        check_db: assert (db_out == (pcl_db ? f_pcl : 8'hff));
        check_adl: assert (adl_out == (pcl_adl ? f_pcl : 8'hff));

        // PCL increments through PCLS, with a carry out of 0xFF
        reach_wrap: cover (f_phi2_load && pcl_adl && adl_out == 8'h00
            && f_pcl_was == 8'hff);
        reach_pclc: cover (pclc && f_select == 8'hff);
        // A jump: ADL into PCLS, then into PCL without incrementing
        reach_jump: cover (f_phi2_load && pcl_db && db_out != 8'h00
            && db_out != 8'hff && db_out != f_pcl_was + 8'd1);
        // PCL holds on a metaclock edge while Phi2 is low, even though
        // PCLS + 1/PC differs
        reach_hold: cover (f_metaclock_rose && !f_phi2_was && pcl_db
            && db_out != f_incremented[7:0]);
    end
endmodule
