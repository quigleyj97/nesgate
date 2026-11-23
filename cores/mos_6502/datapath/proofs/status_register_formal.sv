// Properties of the status register (P), phase by phase, with real Phi1/Phi2
// clocks (two_phase_clock.sv).
//
// The harness keeps no model of the register's latches. Each property relates
// a flag at the end of Phi1 to that phase's inputs and to the flag's output
// at the end of the phase before, as status_register.vhdl documents:
//
// - A flag loads during Phi1 from the sources the random logic selects. Each
//   selected source puts its value on the flag latch's input node and an
//   unselected one releases it, so with several selected the flag takes their
//   AND (a 0 from any of them wins). The sources are:
//   - C: DB bit 0 (DB0/C), IR5 (IR5/C), ACR (ACR/C)
//   - Z: DB bit 1 (DB1/Z), whether DB is 0 (DBZ/Z)
//   - I: DB bit 2 (DB2/I), IR5 (IR5/I)
//   - D: DB bit 3 (DB3/D), IR5 (IR5/D)
//   - V: DB bit 6 (DB6/V), AVR (AVR/V), 1 (1/V), 0 (0/V)
//   - N: DB bit 7 (DB7/N)
// - A flag with no source selected holds, and every flag holds through Phi2.
// - BRK6E: I_OUT reads as set while BRK6E is high, and the I latch loads a 1
//   during a Phi1 that BRK6E covers, unless DB2/I or IR5/I loads it instead.
//   I_OUT hides the I latch during BRK6E, so the harness follows the latch
//   as that rule defines it.
// - P/DB pushes N, V, 1, B_OUT, D, I, Z, C (bit 7 to bit 0), and a disabled
//   DB port drives all ones, releasing the bus.
//
// Each input changes only as a phase starts. Every flag powers up clear.
module status_register_formal (
    input metaclock,
    input end_phase,
    input [7:0] db_in,
    input p_db,
    input ir5,
    input acr,
    input avr,
    input db0_c,
    input ir5_c,
    input acr_c,
    input db1_z,
    input dbz_z,
    input db2_i,
    input ir5_i,
    input db3_d,
    input ir5_d,
    input db6_v,
    input avr_v,
    input one_v,
    input zero_v,
    input db7_n,
    input brk6e,
    input b_out
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

    wire [7:0] db_out;
    wire c_out, z_out, i_out, d_out, v_out, n_out;

    status_register dut (
        .phi1(phi1),
        .db_bus_in(db_in),
        .db_bus_out(db_out),
        .enable_P_DB(p_db),
        .signal_IR5(ir5),
        .signal_ACR(acr),
        .signal_AVR(avr),
        .signal_DB0_C(db0_c),
        .signal_IR5_C(ir5_c),
        .signal_ACR_C(acr_c),
        .signal_DB1_Z(db1_z),
        .signal_DBZ_Z(dbz_z),
        .signal_DB2_I(db2_i),
        .signal_IR5_I(ir5_i),
        .signal_DB3_D(db3_d),
        .signal_IR5_D(ir5_d),
        .signal_DB6_V(db6_v),
        .signal_AVR_V(avr_v),
        .signal_1_V(one_v),
        .signal_0_V(zero_v),
        .signal_DB7_N(db7_n),
        .brk_cycle_6_end_BRK6E(brk6e),
        .break_flag_B_OUT(b_out),
        .carry_flag_C_OUT(c_out),
        .zero_flag_Z_OUT(z_out),
        .interrupt_disable_I_OUT(i_out),
        .decimal_flag_D_OUT(d_out),
        .overflow_flag_V_OUT(v_out),
        .negative_flag_N_OUT(n_out),
        .metaclock(metaclock)
    );

    // Each input only changes as a phase starts
    wire [36:0] f_inputs = {db_in, p_db, ir5, acr, avr, db0_c, ir5_c, acr_c,
        db1_z, dbz_z, db2_i, ir5_i, db3_d, ir5_d, db6_v, avr_v, one_v, zero_v,
        db7_n, brk6e, b_out};
    reg f_past_valid = 1'b0;
    reg [36:0] f_inputs_was = 37'b0;
    always @(posedge metaclock) begin
        f_past_valid <= 1'b1;
        f_inputs_was <= f_inputs;
    end
    always @* begin
        if (f_past_valid && !first_edge) begin
            assume_inputs_hold: assume (f_inputs == f_inputs_was);
        end
    end

    // What a source puts on a flag's input node: its value while selected,
    // or 1 (released) while not
    function source(input selected, input value);
        source = value || !selected;
    endfunction

    // The flags (N V D Z C) at the end of the phase before
    wire [4:0] f_flags = {n_out, v_out, d_out, z_out, c_out};
    reg [4:0] f_flags_phase = 5'b0;
    // The I latch, as the BRK6E rule above defines it, from the end of the
    // last Phi1
    reg f_i = 1'b0;

    wire f_c_selected = db0_c || ir5_c || acr_c;
    wire f_c_node = source(db0_c, db_in[0]) && source(ir5_c, ir5)
        && source(acr_c, acr);
    wire f_z_selected = db1_z || dbz_z;
    wire f_z_node = source(db1_z, db_in[1]) && source(dbz_z, db_in == 8'b0);
    wire f_i_selected = db2_i || ir5_i;
    wire f_i_node = source(db2_i, db_in[2]) && source(ir5_i, ir5);
    wire f_d_selected = db3_d || ir5_d;
    wire f_d_node = source(db3_d, db_in[3]) && source(ir5_d, ir5);
    wire f_v_selected = db6_v || avr_v || one_v || zero_v;
    wire f_v_node = source(db6_v, db_in[6]) && source(avr_v, avr)
        && source(one_v, 1'b1) && source(zero_v, 1'b0);

    wire f_c_was = f_flags_phase[0], f_z_was = f_flags_phase[1];
    wire f_d_was = f_flags_phase[2], f_v_was = f_flags_phase[3];
    wire f_n_was = f_flags_phase[4];
    wire f_i_next = f_i_selected ? f_i_node : brk6e ? 1'b1 : f_i;

    always @(posedge metaclock) begin
        if (last_edge) f_flags_phase <= f_flags;
        if (phi1 && last_edge) f_i <= f_i_next;
    end

    always @* begin
        // The end of Phi1: each flag from its selected sources, or held
        if (phi1 && last_edge) begin
            check_c: assert (c_out == (f_c_selected ? f_c_node : f_c_was));
            check_z: assert (z_out == (f_z_selected ? f_z_node : f_z_was));
            check_i: assert (i_out == (f_i_next || brk6e));
            check_d: assert (d_out == (f_d_selected ? f_d_node : f_d_was));
            check_v: assert (v_out == (f_v_selected ? f_v_node : f_v_was));
            check_n: assert (n_out == (db7_n ? db_in[7] : f_n_was));
            check_push_phi1: assert (db_out == (p_db
                ? {n_out, v_out, 1'b1, b_out, d_out, f_i_next, z_out, c_out}
                : 8'hff));
        end
        // Every flag holds through Phi2, whatever is selected
        if (phi2) begin
            check_hold_phi2: assert (f_flags == f_flags_phase);
            check_i_phi2: assert (i_out == (f_i || brk6e));
            check_push_phi2: assert (db_out == (p_db
                ? {n_out, v_out, 1'b1, b_out, d_out, f_i, z_out, c_out}
                : 8'hff));
        end
    end

    always @* begin
        if (phi1 && last_edge) begin
            reach_c_from_acr: cover (acr_c && !db0_c && !ir5_c && acr && !f_c_was);
            reach_c_from_ir5: cover (ir5_c && !db0_c && !acr_c && ir5 && !f_c_was);
            reach_z_from_dbz: cover (dbz_z && !db1_z && db_in == 8'b0 && !f_z_was);
            reach_z_not_zero: cover (dbz_z && !db1_z && db_in == 8'h01 && f_z_was);
            reach_v_clear: cover (zero_v && !one_v && !db6_v && !avr_v && f_v_was);
            reach_plp: cover (db0_c && db1_z && db2_i && db3_d && db6_v && db7_n
                && !ir5_c && !acr_c && !dbz_z && !ir5_i && !ir5_d && !avr_v
                && !one_v && !zero_v && !brk6e
                && {n_out, v_out, d_out, i_out, z_out, c_out} == 6'b101101);
            // Two sources at once: a 0 from either one wins
            reach_c_wired_and: cover (db0_c && acr_c && db_in[0] && !acr && f_c_was);
            reach_v_wired_and: cover (one_v && avr_v && !avr && f_v_was);
            reach_z_wired_and: cover (db1_z && dbz_z && db_in[1] && f_z_was);
            // BRK6E sets the I latch
            reach_brk6e: cover (brk6e && !f_i_selected && !f_i);
            // DB2/I loads I while BRK6E still forces I_OUT
            reach_brk6e_db2_i: cover (brk6e && db2_i && !db_in[2] && f_i);
            reach_push_b: cover (p_db && db_out[4] && !db_out[2] && i_out);
        end
        if (phi2 && last_edge) begin
            // Selecting during Phi2 leaves the flags alone
            reach_phi2_hold: cover (db7_n && n_out != db_in[7]);
            // The I latch, clear once BRK6E ends, after DB2/I cleared it
            reach_i_after_brk6e: cover (!brk6e && !i_out && f_flags_phase != 5'b0);
        end
    end
endmodule
