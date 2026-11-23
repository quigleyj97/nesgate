// End-to-end properties of the datapath, phase by phase, with real Phi1/Phi2
// clocks (two_phase_clock.sv): every register, wired to the SB, DB, ADH and
// ADL buses through the bus multiplexer, as synthesis sees it.
//
// The harness keeps no model of the netlist's registers or of the bus
// multiplexer. The four buses, the address pins, the data pins and the flags
// are outputs, so each property relates them at the end of a phase to that
// phase's inputs and to the outputs at the end of the phase before. Every
// register loads from the bus the datapath reads, as the DUT's own bus
// outputs show it. The registers that aren't outputs (A, X, Y, the stack
// pointer's two latches, DL, the data output register, PCLS, PCHS, PCL, PCH
// and the I latch) are followed as their documentation defines them, a phase
// at a time:
//
// - A, X, Y and the stack pointer's input latch take SB (SB/AC, SB/X, SB/Y,
//   SB/S), and hold otherwise. The stack pointer's output latch, S, takes the
//   input latch during Phi2.
// - DL takes the data pins during Phi2, and the data output register takes
//   DB during Phi1. The data pins drive the data output register during Phi2
//   of a write (R/W low), and read all ones otherwise.
// - The address bus registers take ADH (ADH/ABH) and ADL (ADL/ABL) during
//   Phi1, and hold otherwise.
// - During Phi1, PCLS takes PCL (PCL/PCL) or ADL (ADL/PCL), and PCHS takes
//   PCH (PCH/PCH) or ADH (ADH/PCH). During Phi2, PCL takes PCLS + 1/PC, and
//   PCH takes PCHS plus the carry out of that.
// - The flags load during Phi1 from DB, IR5, ACR and AVR, each from the AND
//   of its selected sources, as in status_register_formal.sv, and hold
//   otherwise. I_OUT is the I latch or BRK6E.
// - Each bus is a precharged wired-AND node: it reads the AND of every driver
//   on it, inside the datapath and outside it (drive_*), and a driver that
//   isn't enabled puts all ones on it. The open drain MOSFETs (0/ADL0-2,
//   0/ADH0, 0/ADH(1-7)) are drivers that put 0 on their bits. SB/DB and
//   SB/ADH join SB with DB and ADH into one node. Unofficial opcodes like SBX
//   rely on this.
//
// The random logic loads A, X, Y and the stack pointer's input latch only
// outside Phi2, never selects both of PCLS's or both of PCHS's sources, and
// never pushes P (P/DB) while DBZ/Z loads Z from DB during Phi1, which would
// loop Z through an inverter. The harness assumes the same. Each input changes only as a phase starts.
// Everything powers up as 0.
module datapath_formal (
    input metaclock,
    input end_phase,

    input [7:0] data_in,
    input [7:0] drive_sb,
    input [7:0] drive_db,
    input [7:0] drive_adh,
    input [7:0] drive_adl,

    input sb_db,
    input sb_adh,
    input zero_adl0,
    input zero_adl1,
    input zero_adl2,
    input zero_adh0,
    input zero_adh_1_7,

    input sb_ac,
    input ac_sb,
    input ac_db,
    input sb_x,
    input x_sb,
    input sb_y,
    input y_sb,
    input sb_s,
    input s_sb,
    input s_adl,
    input adh_abh,
    input adl_abl,
    input pcl_pcl,
    input adl_pcl,
    input i_pc,
    input pcl_db,
    input pcl_adl,
    input pch_pch,
    input adh_pch,
    input pch_db,
    input pch_adh,
    input dl_db,
    input dl_adl,
    input dl_adh,
    input r_not_w,

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

    wire [7:0] data_out;
    wire [15:0] address;
    wire [7:0] bus_sb, bus_db, bus_adh, bus_adl;
    wire c_out, z_out, i_out, d_out, v_out, n_out;

    mos_6502_datapath dut (
        .data_in(data_in),
        .data_out(data_out),
        .address(address),
        .phi1(phi1),
        .phi2(phi2),
        .metaclock(metaclock),
        .drive_SB(drive_sb),
        .drive_DB(drive_db),
        .drive_ADH(drive_adh),
        .drive_ADL(drive_adl),
        .databus_SB(bus_sb),
        .databus_DB(bus_db),
        .databus_ADH(bus_adh),
        .databus_ADL(bus_adl),
        .connect_SB_DB(sb_db),
        .connect_SB_ADH(sb_adh),
        .clear_0_ADL0(zero_adl0),
        .clear_0_ADL1(zero_adl1),
        .clear_0_ADL2(zero_adl2),
        .clear_0_ADH0(zero_adh0),
        .clear_0_ADH_1_7(zero_adh_1_7),
        .load_SB_AC(sb_ac),
        .output_enable_AC_SB(ac_sb),
        .output_enable_AC_DB(ac_db),
        .load_SB_X(sb_x),
        .output_enable_X_SB(x_sb),
        .load_SB_Y(sb_y),
        .output_enable_Y_SB(y_sb),
        .load_SB_S(sb_s),
        .output_enable_S_SB(s_sb),
        .output_enable_S_ADL(s_adl),
        .load_ADH_ABH(adh_abh),
        .load_ADL_ABL(adl_abl),
        .load_PCL_PCL(pcl_pcl),
        .load_ADL_PCL(adl_pcl),
        .signal_I_PC(i_pc),
        .output_enable_PCL_DB(pcl_db),
        .output_enable_PCL_ADL(pcl_adl),
        .load_PCH_PCH(pch_pch),
        .load_ADH_PCH(adh_pch),
        .output_enable_PCH_DB(pch_db),
        .output_enable_PCH_ADH(pch_adh),
        .output_enable_DL_DB(dl_db),
        .output_enable_DL_ADL(dl_adl),
        .output_enable_DL_ADH(dl_adh),
        .signal_R_NOT_W(r_not_w),
        .output_enable_P_DB(p_db),
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
        .signal_BRK6E(brk6e),
        .signal_B_OUT(b_out),
        .carry_flag_C_OUT(c_out),
        .zero_flag_Z_OUT(z_out),
        .interrupt_disable_I_OUT(i_out),
        .decimal_flag_D_OUT(d_out),
        .overflow_flag_V_OUT(v_out),
        .negative_flag_N_OUT(n_out)
    );

    // #region Inputs
    wire [91:0] f_inputs = {data_in, drive_sb, drive_db, drive_adh, drive_adl,
        sb_db, sb_adh, zero_adl0, zero_adl1, zero_adl2, zero_adh0, zero_adh_1_7,
        sb_ac, ac_sb, ac_db, sb_x, x_sb, sb_y, y_sb, sb_s, s_sb, s_adl,
        adh_abh, adl_abl, pcl_pcl, adl_pcl, i_pc, pcl_db, pcl_adl,
        pch_pch, adh_pch, pch_db, pch_adh, dl_db, dl_adl, dl_adh, r_not_w,
        p_db, ir5, acr, avr, db0_c, ir5_c, acr_c, db1_z, dbz_z, db2_i, ir5_i,
        db3_d, ir5_d, db6_v, avr_v, one_v, zero_v, db7_n, brk6e, b_out};

    // Each input only changes as a phase starts
    reg f_past_valid = 1'b0;
    reg [91:0] f_inputs_was = 92'b0;
    always @(posedge metaclock) begin
        f_past_valid <= 1'b1;
        f_inputs_was <= f_inputs;
    end
    always @* begin
        if (f_past_valid && !first_edge) begin
            assume_inputs_hold: assume (f_inputs == f_inputs_was);
        end
        if (phi2) begin
            assume_no_sb_load_phi2: assume (!sb_ac && !sb_x && !sb_y && !sb_s);
        end
        assume_one_pcl_source: assume (!(pcl_pcl && adl_pcl));
        assume_one_pch_source: assume (!(pch_pch && adh_pch));
        // P on DB while DBZ/Z loads Z from DB would loop Z through an
        // inverter, and oscillate
        if (phi1) begin
            assume_no_dbz_push: assume (!(p_db && dbz_z));
        end
    end
    // #endregion

    // #region Registers
    // Each register as it was at the end of the phase before. All of them
    // power up as 0.
    reg [7:0] f_ac = 8'b0, f_x = 8'b0, f_y = 8'b0;
    reg [7:0] f_s_in = 8'b0, f_s = 8'b0;
    reg [7:0] f_dl = 8'b0, f_dor = 8'b0;
    reg [7:0] f_pcls = 8'b0, f_pchs = 8'b0, f_pcl = 8'b0, f_pch = 8'b0;
    reg f_i = 1'b0;
    // The outputs at the end of the phase before
    reg [15:0] f_address_phase = 16'b0;
    reg [4:0] f_flags_phase = 5'b0;

    // Each register at the end of this phase, from this phase's inputs and
    // the buses as the datapath reads them
    wire [7:0] f_ac_now = sb_ac ? bus_sb : f_ac;
    wire [7:0] f_x_now = sb_x ? bus_sb : f_x;
    wire [7:0] f_y_now = sb_y ? bus_sb : f_y;
    wire [7:0] f_s_in_now = sb_s ? bus_sb : f_s_in;
    wire [7:0] f_s_now = phi2 ? f_s_in : f_s;
    wire [7:0] f_dl_now = phi2 ? data_in : f_dl;
    wire [7:0] f_dor_now = phi1 ? bus_db : f_dor;
    wire [7:0] f_pcls_now = phi1 && pcl_pcl ? f_pcl
        : phi1 && adl_pcl ? bus_adl : f_pcls;
    wire [7:0] f_pchs_now = phi1 && pch_pch ? f_pch
        : phi1 && adh_pch ? bus_adh : f_pchs;
    wire [8:0] f_pcl_incremented = {1'b0, f_pcls} + {8'b0, i_pc};
    wire [7:0] f_pcl_now = phi2 ? f_pcl_incremented[7:0] : f_pcl;
    wire [7:0] f_pch_now = phi2 ? f_pchs + {7'b0, f_pcl_incremented[8]} : f_pch;
    wire [15:0] f_address_now = {
        phi1 && adh_abh ? bus_adh : f_address_phase[15:8],
        phi1 && adl_abl ? bus_adl : f_address_phase[7:0]};
    // #endregion

    // #region Flags
    // What a source puts on a flag's input node: its value while selected,
    // or 1 (released) while not
    function source(input selected, input value);
        source = value || !selected;
    endfunction

    wire f_c_was = f_flags_phase[0], f_z_was = f_flags_phase[1];
    wire f_d_was = f_flags_phase[2], f_v_was = f_flags_phase[3];
    wire f_n_was = f_flags_phase[4];
    wire f_c_now = phi1 && (db0_c || ir5_c || acr_c)
        ? source(db0_c, bus_db[0]) && source(ir5_c, ir5) && source(acr_c, acr)
        : f_c_was;
    wire f_z_now = phi1 && (db1_z || dbz_z)
        ? source(db1_z, bus_db[1]) && source(dbz_z, bus_db == 8'b0)
        : f_z_was;
    wire f_i_now = phi1 && (db2_i || ir5_i)
        ? source(db2_i, bus_db[2]) && source(ir5_i, ir5)
        : phi1 && brk6e ? 1'b1 : f_i;
    wire f_d_now = phi1 && (db3_d || ir5_d)
        ? source(db3_d, bus_db[3]) && source(ir5_d, ir5)
        : f_d_was;
    wire f_v_now = phi1 && (db6_v || avr_v || one_v || zero_v)
        ? source(db6_v, bus_db[6]) && source(avr_v, avr) && !zero_v
        : f_v_was;
    wire f_n_now = phi1 && db7_n ? bus_db[7] : f_n_was;
    wire [4:0] f_flags = {n_out, v_out, d_out, z_out, c_out};
    // #endregion

    // #region Buses
    // What a driver puts on a bus: its value while enabled, or all ones (the
    // identity of a wired-AND) while not
    function [7:0] when_enabled(input enable, input [7:0] value);
        when_enabled = enable ? value : 8'hff;
    endfunction

    wire [7:0] f_pushed_p = {n_out, v_out, 1'b1, b_out, d_out, f_i_now, z_out, c_out};

    // Everything driving each bus on its own, wired-AND together
    wire [7:0] f_on_sb = drive_sb
        & when_enabled(ac_sb, f_ac_now)
        & when_enabled(x_sb, f_x_now)
        & when_enabled(y_sb, f_y_now)
        & when_enabled(s_sb, f_s_now);
    wire [7:0] f_on_db = drive_db
        & when_enabled(ac_db, f_ac_now)
        & when_enabled(p_db, f_pushed_p)
        & when_enabled(dl_db, f_dl_now)
        & when_enabled(pcl_db, f_pcl_now)
        & when_enabled(pch_db, f_pch_now);
    wire [7:0] f_on_adh = drive_adh
        & when_enabled(dl_adh, f_dl_now)
        & when_enabled(pch_adh, f_pch_now)
        & when_enabled(zero_adh0, 8'hfe)
        & when_enabled(zero_adh_1_7, 8'h01);
    wire [7:0] f_on_adl = drive_adl
        & when_enabled(s_adl, f_s_now)
        & when_enabled(dl_adl, f_dl_now)
        & when_enabled(pcl_adl, f_pcl_now)
        & when_enabled(zero_adl0, 8'hfe)
        & when_enabled(zero_adl1, 8'hfd)
        & when_enabled(zero_adl2, 8'hfb);
    // SB/DB and SB/ADH join SB with DB and ADH into one node
    wire [7:0] f_sb_node = f_on_sb
        & when_enabled(sb_db, f_on_db)
        & when_enabled(sb_adh, f_on_adh);
    // #endregion

    always @(posedge metaclock) begin
        if (last_edge) begin
            f_ac <= f_ac_now;
            f_x <= f_x_now;
            f_y <= f_y_now;
            f_s_in <= f_s_in_now;
            f_s <= f_s_now;
            f_dl <= f_dl_now;
            f_dor <= f_dor_now;
            f_pcls <= f_pcls_now;
            f_pchs <= f_pchs_now;
            f_pcl <= f_pcl_now;
            f_pch <= f_pch_now;
            f_i <= f_i_now;
            f_address_phase <= address;
            f_flags_phase <= f_flags;
        end
    end

    always @* begin
        // The end of each phase, once every register has settled
        if (last_edge) begin
            check_sb: assert (bus_sb == f_sb_node);
            check_db: assert (bus_db == (sb_db ? f_sb_node : f_on_db));
            check_adh: assert (bus_adh == (sb_adh ? f_sb_node : f_on_adh));
            check_adl: assert (bus_adl == f_on_adl);
            check_address: assert (address == f_address_now);
            check_c: assert (c_out == f_c_now);
            check_z: assert (z_out == f_z_now);
            check_i: assert (i_out == (f_i_now || brk6e));
            check_d: assert (d_out == f_d_now);
            check_v: assert (v_out == f_v_now);
            check_n: assert (n_out == f_n_now);
        end
        // The address pins and the flags hold through Phi2, and the data pins
        // drive the data output register through Phi2 of a write
        if (phi2) begin
            check_address_phi2: assert (address == f_address_phase);
            check_flags_phi2: assert (f_flags == f_flags_phase);
            check_data_out_phi2: assert (data_out == when_enabled(!r_not_w, f_dor));
        end else begin
            check_data_out_phi1: assert (data_out == 8'hff);
        end
    end

    // #region Settling
    // DB settles within a phase's first two metaclock edges, as
    // two_phase_clock.sv's last_edge relies on: from the third edge of Phi1
    // on, it reads the same on every edge. Z's DBZ/Z source is the NOR of all
    // eight DB bits, which PDR can't prove stable as a whole word, but can
    // one bit at a time, here. datapath.sby proves this on its own (the lemma
    // task) and assumes it to prove check_z and check_flags_phi2 (the z task).
    reg [7:0] f_db_was = 8'hff;
    reg f_first_edge_was = 1'b1;
    always @(posedge metaclock) begin
        f_db_was <= bus_db;
        f_first_edge_was <= first_edge;
    end
    always @* begin
        if (f_past_valid && phi1 && !first_edge && !f_first_edge_was) begin
            lemma_db_settled: assert (bus_db == f_db_was);
        end
    end
    // #endregion

    always @* begin
        if (last_edge) begin
            // TAX: A onto SB, into X, then X back out
            reach_transfer: cover (x_sb && !ac_sb && !y_sb && !s_sb
                && !sb_db && !sb_adh && drive_sb == 8'hff
                && bus_sb == 8'h5a && f_ac == 8'h5a);
            // A byte read from the pins reaches the address bus through DL
            // and ADL
            reach_read_to_address: cover (address == 16'h00a5 && f_dl == 8'ha5);
            // PC increments onto the address buses, carrying from PCL into PCH
            reach_pc_carry: cover (phi1 && f_pch == 8'h01 && f_pcl == 8'h00
                && pch_adh && pcl_adl && bus_adh == 8'h01 && bus_adl == 8'h00);
            // A store: X through SB/DB into the data output register, then out
            reach_store: cover (phi2 && data_out == 8'h3c && f_x == 8'h3c);
            // The flags from DB, as PLP sets them
            reach_plp: cover (phi1 && db0_c && db1_z && db2_i && db3_d && db6_v
                && db7_n && !brk6e
                && {n_out, v_out, d_out, i_out, z_out, c_out} == 6'b110011);
            // An ALU result on SB, through SB/ADH onto ADH
            reach_sb_adh: cover (sb_adh && !sb_db && drive_adh == 8'hff
                && !dl_adh && !pch_adh && !zero_adh0 && !zero_adh_1_7
                && bus_adh == 8'h42 && drive_sb == 8'h42);
            // A and X on SB at once read their wired-AND, as SBX needs
            reach_two_drivers: cover (ac_sb && x_sb && !y_sb && !s_sb && !sb_db
                && !sb_adh && drive_sb == 8'hff && f_ac == 8'hf0 && f_x == 8'h3c
                && bus_sb == 8'h30);
            // The NMI vector's low byte, from the open drain MOSFETs alone
            reach_vector: cover (bus_adl == 8'hfa && drive_adl == 8'hff
                && !s_adl && !dl_adl && !pcl_adl);
        end
    end
endmodule
