// Properties of the program counter high byte: the select register (PCHS),
// the increment logic, and PCH. Clocked like program_counter_low_formal.sv,
// with the metaclock and Phi2 as independent inputs.
//
// The increment logic is split into two nibbles in the design. The model
// is a plain 8-bit increment by PCLC, so the proof shows that the nibbles
// carry into each other correctly, and that PCH wraps from 0xFF to 0x00.
module program_counter_high_formal (
    input metaclock,
    input phi2,
    input pch_pch,
    input adh_pch,
    input pclc,
    input pch_db,
    input pch_adh,
    input [7:0] adh_in
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

    reg f_past_valid = 1'b0;
    reg f_metaclock_was = 1'b0;
    reg f_phi2_was = 1'b0;
    reg [7:0] f_select_was = 8'b0;
    reg [7:0] f_select_next_was = 8'b0;
    reg [7:0] f_pch_was = 8'b0;
    reg [7:0] f_pch_next_was = 8'b0;

    wire f_metaclock_rose = metaclock && !f_metaclock_was;
    wire f_phi2_rose = phi2 && !f_phi2_was;

    wire [7:0] f_select = f_metaclock_rose ? f_select_next_was : f_select_was;
    wire [7:0] f_pch = f_phi2_rose ? f_pch_next_was : f_pch_was;
    // PCHS takes PCH (PCH/PCH), or else ADH (ADH/PCH), or else holds
    wire [7:0] f_select_next = pch_pch ? f_pch : adh_pch ? adh_in : f_select;

    always @($global_clock) begin
        f_past_valid <= 1'b1;
        f_metaclock_was <= metaclock;
        f_phi2_was <= phi2;
        f_select_was <= f_select;
        f_select_next_was <= f_select_next;
        f_pch_was <= f_pch;
        f_pch_next_was <= f_select + {7'b0, pclc};
    end

    always @* begin
        if (!f_past_valid) begin
            assume_power_up: assume (!metaclock && !phi2);
        end

        check_db: assert (db_out == (pch_db ? f_pch : 8'hff));
        check_adh: assert (adh_out == (pch_adh ? f_pch : 8'hff));

        // The low nibble carries into the high nibble
        reach_nibble_carry: cover (f_phi2_rose && pch_db && db_out == 8'h30
            && f_pch_was == 8'h2f);
        reach_wrap: cover (f_phi2_rose && pch_adh && adh_out == 8'h00
            && f_pch_was == 8'hff);
        // A jump: ADH into PCHS, then into PCH
        reach_jump: cover (f_phi2_rose && pch_db && db_out != 8'h00
            && db_out != 8'hff && db_out != f_pch_was
            && db_out != f_pch_was + 8'd1);
    end
endmodule
