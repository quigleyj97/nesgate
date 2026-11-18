// Properties of the status register (P), checked on every metaclock edge.
// The DB port goes through the same precharge techmap as synthesis (see
// techmaps/precharge_tribuf.v), so a disabled port reads all ones.
//
// The model loads each flag from its one selected source while Phi1 is high,
// and holds it when no source, or more than one, is selected (the random
// logic never selects more than one).
module status_register_formal (
    input metaclock,
    input phi1,
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

    // The model of each flag, all powering up as 0
    reg f_c = 1'b0, f_z = 1'b0, f_i = 1'b0, f_d = 1'b0, f_v = 1'b0, f_n = 1'b0;

    wire [1:0] f_c_sources = db0_c + ir5_c + acr_c;
    wire [1:0] f_i_sources = db2_i + ir5_i;
    wire [2:0] f_v_sources = db6_v + avr_v + one_v + zero_v;

    always @(posedge metaclock) begin
        if (phi1) begin
            if (f_c_sources == 1) f_c <= db0_c ? db_in[0] : ir5_c ? ir5 : acr;
            if (db1_z != dbz_z) f_z <= db1_z ? db_in[1] : db_in == 8'b0;
            if (f_i_sources == 1) f_i <= db2_i ? db_in[2] : ir5;
            else if (brk6e) f_i <= 1'b1;
            if (db3_d != ir5_d) f_d <= db3_d ? db_in[3] : ir5;
            if (f_v_sources == 1) f_v <= db6_v ? db_in[6] : avr_v ? avr : one_v;
            if (db7_n) f_n <= db_in[7];
        end
    end

    always @* begin
        check_c: assert (c_out == f_c);
        check_z: assert (z_out == f_z);
        check_i: assert (i_out == (f_i || brk6e));
        check_d: assert (d_out == f_d);
        check_v: assert (v_out == f_v);
        check_n: assert (n_out == f_n);
        // Bit 5 is pushed set, and bit 4 is B_OUT
        check_push: assert (db_out == (p_db
            ? {f_n, f_v, 1'b1, b_out, f_d, f_i, f_z, f_c} : 8'hff));
    end

    reg f_past_valid = 1'b0;
    always @(posedge metaclock) f_past_valid <= 1'b1;

    always @(posedge metaclock) begin
        if (f_past_valid) begin
            reach_c_from_acr: cover ($past(phi1 && acr_c && !db0_c && !ir5_c && acr) && c_out);
            reach_c_from_ir5: cover ($past(phi1 && ir5_c && !db0_c && !acr_c && ir5) && c_out);
            reach_z_from_dbz: cover ($past(phi1 && dbz_z && !db1_z && db_in == 8'b0) && z_out);
            reach_z_not_zero: cover ($past(phi1 && dbz_z && !db1_z && db_in == 8'h01)
                && !z_out && $past(z_out));
            reach_v_set_clear: cover ($past(phi1 && zero_v && !one_v && !db6_v && !avr_v)
                && !v_out && $past(v_out));
            reach_plp: cover ($past(phi1 && db0_c && db1_z && db2_i && db3_d && db6_v && db7_n)
                && {n_out, v_out, d_out, i_out, z_out, c_out} == 6'b101101);
            // Selecting during Phi2 leaves the flags alone
            reach_phi2_hold: cover ($past(!phi1 && db7_n) && n_out != $past(db_in[7]));
            // Two sources at once hold the flag
            reach_conflict_hold: cover ($past(phi1 && db0_c && acr_c && !ir5_c)
                && c_out != $past(db_in[0]) && c_out != $past(acr));
            // BRK6E sets I, which stays set once BRK6E ends
            reach_brk6e: cover ($past(phi1 && brk6e && !db2_i && !ir5_i && !f_i)
                && !brk6e && i_out);
            reach_push_b: cover (p_db && db_out[4] && db_out[2] == 1'b0 && i_out);
        end
    end
endmodule
