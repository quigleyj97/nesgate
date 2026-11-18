// End-to-end properties of the datapath: every register, wired to the SB,
// DB, ADH and ADL buses through the bus multiplexer, as synthesis sees it.
//
// Every latch in the datapath is on the metaclock. The proof runs with
// SymbiYosys's multiclock mode so that the metaclock is an ordinary input:
// every step is a tick of the global formal clock, and the
// metaclock, Phi1 and Phi2 are ordinary inputs that can change on any step,
// in any order, independently of each other.
//
// The harness keeps a model of every register and checks every output
// against it on every step. Each register in the model keeps the value it
// would take on its next clock edge, computed from the step before, like the
// netlist's registers. The registers that aren't outputs are checked through
// the buses they drive.
//
// Any number of drivers can be enabled on a bus at once, inside the datapath
// or outside it (drive_*): the bus reads their wired-AND, as on the real chip.
// Unofficial opcodes like SBX rely on this.
//
// Every subunit drives all ones while it isn't enabled, and the datapath ANDs
// each bus's drivers together, so an undriven bus reads all ones.
module datapath_formal (
    input metaclock,
    input phi1,
    input phi2,

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

    // #region Clocks
    reg f_past_valid = 1'b0;
    reg f_metaclock_was = 1'b0;
    wire f_metaclock_rose = metaclock && !f_metaclock_was;
    // #endregion

    // #region Registers
    // Each register as it was on the step before (_was), and the value it
    // would have taken on an edge (_next_was). All of them power up as 0.
    reg [7:0] f_ac_was = 8'b0, f_ac_next_was = 8'b0;
    reg [7:0] f_x_was = 8'b0, f_x_next_was = 8'b0;
    reg [7:0] f_y_was = 8'b0, f_y_next_was = 8'b0;
    reg [7:0] f_s_in_was = 8'b0, f_s_in_next_was = 8'b0;
    reg [7:0] f_s_was = 8'b0, f_s_next_was = 8'b0;
    reg [5:0] f_p_was = 6'b0, f_p_next_was = 6'b0;
    reg [7:0] f_abh_was = 8'b0, f_abh_next_was = 8'b0;
    reg [7:0] f_abl_was = 8'b0, f_abl_next_was = 8'b0;
    reg [7:0] f_dl_was = 8'b0, f_dl_next_was = 8'b0;
    reg [7:0] f_dor_was = 8'b0, f_dor_next_was = 8'b0;
    reg [7:0] f_pcls_was = 8'b0, f_pcls_next_was = 8'b0;
    reg [7:0] f_pchs_was = 8'b0, f_pchs_next_was = 8'b0;
    reg [7:0] f_pcl_was = 8'b0, f_pcl_next_was = 8'b0;
    reg [7:0] f_pch_was = 8'b0, f_pch_next_was = 8'b0;

    // Every latch is on the metaclock
    wire [7:0] f_ac = f_metaclock_rose ? f_ac_next_was : f_ac_was;
    wire [7:0] f_x = f_metaclock_rose ? f_x_next_was : f_x_was;
    wire [7:0] f_y = f_metaclock_rose ? f_y_next_was : f_y_was;
    wire [7:0] f_s_in = f_metaclock_rose ? f_s_in_next_was : f_s_in_was;
    wire [7:0] f_s = f_metaclock_rose ? f_s_next_was : f_s_was;
    wire [5:0] f_p = f_metaclock_rose ? f_p_next_was : f_p_was;
    wire [7:0] f_abh = f_metaclock_rose ? f_abh_next_was : f_abh_was;
    wire [7:0] f_abl = f_metaclock_rose ? f_abl_next_was : f_abl_was;
    wire [7:0] f_dl = f_metaclock_rose ? f_dl_next_was : f_dl_was;
    wire [7:0] f_dor = f_metaclock_rose ? f_dor_next_was : f_dor_was;
    wire [7:0] f_pcls = f_metaclock_rose ? f_pcls_next_was : f_pcls_was;
    wire [7:0] f_pchs = f_metaclock_rose ? f_pchs_next_was : f_pchs_was;
    wire [7:0] f_pcl = f_metaclock_rose ? f_pcl_next_was : f_pcl_was;
    wire [7:0] f_pch = f_metaclock_rose ? f_pch_next_was : f_pch_was;

    // The flags, in the order they're pushed (N V D I Z C, leaving out bits
    // 5 and 4)
    wire f_n = f_p[5], f_v = f_p[4], f_d = f_p[3];
    wire f_i = f_p[2], f_z = f_p[1], f_c = f_p[0];
    // #endregion

    // #region Buses
    // What a driver puts on a bus: its value while enabled, or all ones (the
    // identity of a wired-AND) while not
    function [7:0] when_enabled(input enable, input [7:0] value);
        when_enabled = enable ? value : 8'hff;
    endfunction

    wire [7:0] f_pushed_p = {f_n, f_v, 1'b1, b_out, f_d, f_i, f_z, f_c};

    // Everything in the datapath driving each bus, wired-AND together
    wire [7:0] f_drivers_sb = when_enabled(ac_sb, f_ac)
        & when_enabled(x_sb, f_x)
        & when_enabled(y_sb, f_y)
        & when_enabled(s_sb, f_s);
    wire [7:0] f_drivers_db = when_enabled(ac_db, f_ac)
        & when_enabled(p_db, f_pushed_p)
        & when_enabled(dl_db, f_dl)
        & when_enabled(pcl_db, f_pcl)
        & when_enabled(pch_db, f_pch);
    wire [7:0] f_drivers_adh = when_enabled(dl_adh, f_dl)
        & when_enabled(pch_adh, f_pch);
    wire [7:0] f_drivers_adl = when_enabled(s_adl, f_s)
        & when_enabled(dl_adl, f_dl)
        & when_enabled(pcl_adl, f_pcl);

    // The bus multiplexer, as in bus_multiplexer_formal.sv: a bit reads 0
    // exactly when something on its node pulls it low
    wire [7:0] f_low_sb = ~f_drivers_sb | ~drive_sb;
    wire [7:0] f_low_db = ~f_drivers_db | ~drive_db;
    wire [7:0] f_low_adh = ~f_drivers_adh | ~drive_adh
        | {{7{zero_adh_1_7}}, zero_adh0};
    wire [7:0] f_low_adl = ~f_drivers_adl | ~drive_adl
        | {5'b0, zero_adl2, zero_adl1, zero_adl0};
    wire [7:0] f_low_sb_node = f_low_sb
        | (sb_db ? f_low_db : 8'b0)
        | (sb_adh ? f_low_adh : 8'b0);

    wire [7:0] f_sb = ~f_low_sb_node;
    wire [7:0] f_db = ~(sb_db ? f_low_sb_node : f_low_db);
    wire [7:0] f_adh = ~(sb_adh ? f_low_sb_node : f_low_adh);
    wire [7:0] f_adl = ~f_low_adl;
    // #endregion

    // #region Next values
    // The status register, as in status_register_formal.sv: each flag loads
    // from its one selected source during Phi1, and holds otherwise
    wire [1:0] f_c_sources = db0_c + ir5_c + acr_c;
    wire [1:0] f_i_sources = db2_i + ir5_i;
    wire [2:0] f_v_sources = db6_v + avr_v + one_v + zero_v;
    wire f_c_next = phi1 && f_c_sources == 1
        ? (db0_c ? f_db[0] : ir5_c ? ir5 : acr) : f_c;
    wire f_z_next = phi1 && db1_z != dbz_z
        ? (db1_z ? f_db[1] : f_db == 8'b0) : f_z;
    wire f_i_next = phi1 && f_i_sources == 1 ? (db2_i ? f_db[2] : ir5)
        : phi1 && brk6e ? 1'b1 : f_i;
    wire f_d_next = phi1 && db3_d != ir5_d ? (db3_d ? f_db[3] : ir5) : f_d;
    wire f_v_next = phi1 && f_v_sources == 1
        ? (db6_v ? f_db[6] : avr_v ? avr : one_v) : f_v;
    wire f_n_next = phi1 && db7_n ? f_db[7] : f_n;

    // The increment logic of PCL and PCH
    wire [8:0] f_pcl_incremented = {1'b0, f_pcls} + {8'b0, i_pc};
    wire f_pclc = f_pcl_incremented[8];

    always @($global_clock) begin
        f_past_valid <= 1'b1;
        f_metaclock_was <= metaclock;

        f_ac_was <= f_ac;
        f_x_was <= f_x;
        f_y_was <= f_y;
        f_s_in_was <= f_s_in;
        f_s_was <= f_s;
        f_p_was <= f_p;
        f_abh_was <= f_abh;
        f_abl_was <= f_abl;
        f_dl_was <= f_dl;
        f_dor_was <= f_dor;
        f_pcls_was <= f_pcls;
        f_pchs_was <= f_pchs;
        f_pcl_was <= f_pcl;
        f_pch_was <= f_pch;

        // A, X, Y and the stack pointer's input latch load from SB
        f_ac_next_was <= sb_ac ? f_sb : f_ac;
        f_x_next_was <= sb_x ? f_sb : f_x;
        f_y_next_was <= sb_y ? f_sb : f_y;
        f_s_in_next_was <= sb_s ? f_sb : f_s_in;
        // The stack pointer's output latch loads from its input latch during
        // Phi2
        f_s_next_was <= phi2 ? f_s_in : f_s;
        f_p_next_was <= {f_n_next, f_v_next, f_d_next, f_i_next, f_z_next, f_c_next};
        // The address bus registers load from ADH and ADL during Phi1
        f_abh_next_was <= phi1 && adh_abh ? f_adh : f_abh;
        f_abl_next_was <= phi1 && adl_abl ? f_adl : f_abl;
        // The data input latch follows the pins during Phi2, and the data
        // output register follows DB during Phi1
        f_dl_next_was <= phi2 ? data_in : f_dl;
        f_dor_next_was <= phi1 ? f_db : f_dor;
        // The program counter select registers load during Phi1
        f_pcls_next_was <= phi1 && pcl_pcl ? f_pcl
            : phi1 && adl_pcl ? f_adl : f_pcls;
        f_pchs_next_was <= phi1 && pch_pch ? f_pch
            : phi1 && adh_pch ? f_adh : f_pchs;
        // PCL and PCH take the incremented select registers during Phi2
        f_pcl_next_was <= phi2 ? f_pcl_incremented[7:0] : f_pcl;
        f_pch_next_was <= phi2 ? f_pchs + {7'b0, f_pclc} : f_pch;
    end
    // #endregion

    always @* begin
        if (!f_past_valid) begin
            assume_power_up: assume (!metaclock && !phi2);
        end

        check_sb: assert (bus_sb == f_sb);
        check_db: assert (bus_db == f_db);
        check_adh: assert (bus_adh == f_adh);
        check_adl: assert (bus_adl == f_adl);
        check_address: assert (address == {f_abh, f_abl});
        check_data_out: assert (data_out == (!r_not_w && phi2 ? f_dor : 8'hff));
        check_c: assert (c_out == f_c);
        check_z: assert (z_out == f_z);
        check_i: assert (i_out == (f_i || brk6e));
        check_d: assert (d_out == f_d);
        check_v: assert (v_out == f_v);
        check_n: assert (n_out == f_n);

        // TAX: A onto SB, into X, then X back out
        reach_transfer: cover (f_past_valid && x_sb && !ac_sb && !y_sb && !s_sb
            && !sb_db && !sb_adh && drive_sb == 8'hff
            && bus_sb == 8'h5a && f_ac == 8'h5a);
        // A byte read from the pins reaches the address bus through DL and ADL
        reach_read_to_address: cover (address[7:0] == 8'ha5 && address[15:8] == 8'h00);
        // PC increments into the address bus, carrying from PCL into PCH
        reach_pc_carry: cover (f_pch == 8'h01 && f_pcl == 8'h00 && pch_adh && pcl_adl
            && bus_adh == 8'h01 && bus_adl == 8'h00);
        // A store: X through SB/DB into the data output register, then out
        reach_store: cover (data_out == 8'h3c && !phi1 && phi2 && f_x == 8'h3c);
        // The flags from DB, as PLP sets them
        reach_plp: cover ({n_out, v_out, d_out, i_out, z_out, c_out} == 6'b110011
            && !brk6e);
        // An ALU result on SB, through SB/ADH onto ADH
        reach_sb_adh: cover (sb_adh && !sb_db && drive_adh == 8'hff
            && !dl_adh && !pch_adh && bus_adh == 8'h42 && drive_sb == 8'h42);
        // A and X on SB at once read their wired-AND, as SBX needs
        reach_two_drivers: cover (ac_sb && x_sb && !y_sb && !s_sb && !sb_db
            && !sb_adh && drive_sb == 8'hff && f_ac == 8'hf0 && f_x == 8'h3c
            && bus_sb == 8'h30);
    end
endmodule
