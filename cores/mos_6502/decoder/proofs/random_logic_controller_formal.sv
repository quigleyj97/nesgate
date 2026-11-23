// Structural properties of the random logic controller, checked on every
// metaclock edge, with Phi1, Phi2, the decoder lines and every other input
// free to change on any edge.
//
// The controller is too large to restate as a model, and nothing documents
// its equations apart from the VHDL. So this harness checks what holds for any
// decoder lines, from the controller's documentation, and leaves what each
// command does to decoder_formal.sv, which drives it from the real decoder:
//
// - Cut-offs: the register, accumulator, ALU input and PC select commands are
//   all off during Phi2, while the buses precharge.
// - Complements: each pair of commands that share one latch (SB/ADD and
//   0/ADD, ADL/PCL and PCL/PCL, ADH/PCH and PCH/PCH, SB/S and S/S) has exactly
//   one side on outside Phi2. The B input gets DB/ADD unless it gets NOT DB or
//   ADL, and the ALU sums unless another operation is selected.
// - Phases: every command latched during Phi2 only changes on a metaclock
//   edge during Phi2 (or when Phi2 cuts it off), and every command latched
//   during Phi1 only changes on an edge during Phi1.
// - Dispatch: SHIFT, MemOP and STOR come from their decoder lines, FETCH only
//   happens while ready, 0/IR injects BRK unless fetching with B_OUT set, and
//   reset and BRK6E restart the cycle counters (TRESX).
module random_logic_controller_formal (
    input metaclock,
    input phi1,
    input phi2,
    input [129:0] decoder_in,
    input ready,
    input ready_phi1,
    input t0,
    input t1,
    input t6,
    input t7,
    input implied,
    input ir5,
    input resp,
    input brk6e,
    input b_out,
    input adl0,
    input acr,
    input c_flag,
    input d_flag,
    input v_flag,
    input n_flag,
    input z_flag,
    input [7:0] db_in
);
    wire tres1, tresx, shift, memop, stor, pc_db, fetch, zero_ir;
    wire x_sb, y_sb, sb_x, sb_y, s_sb, s_adl, sb_s, s_s;
    wire ndb_add, db_add, adl_add, sb_add, zero_add;
    wire ands, eors, ors, srs, sums, i_addc, daa, dsa;
    wire add_sb06, add_sb7, add_adl;
    wire sb_ac, ac_sb, ac_db;
    wire i_pc, pcl_pcl, adl_pcl, pcl_adl, pcl_db, pch_pch, adh_pch, pch_adh, pch_db;
    wire adh_abh, adl_abl, sb_db, sb_adh, zero_adh0, zero_adh17, dl_db, dl_adl, dl_adh;
    wire p_db, db0_c, ir5_c, acr_c, db1_z, dbz_z, db2_i, ir5_i, db3_d, ir5_d;
    wire db6_v, avr_v, zero_v, db7_n;

    random_logic_controller dut (
        .phi1(phi1),
        .phi2(phi2),
        .decoder_in(decoder_in),
        .ready(ready),
        .ready_phi1_ReadyPhi1(ready_phi1),
        .cycle_T0(t0),
        .cycle_T1(t1),
        .rmw_cycle_T6(t6),
        .rmw_cycle_T7(t7),
        .single_byte_IMPLIED(implied),
        .instruction_IR5(ir5),
        .reset_pending_RESP(resp),
        .brk_cycle_6_end_BRK6E(brk6e),
        .break_flag_B_OUT(b_out),
        .vector_0_ADL0(adl0),
        .alu_carry_ACR(acr),
        .carry_flag_C_OUT(c_flag),
        .decimal_flag_D_OUT(d_flag),
        .overflow_flag_V_OUT(v_flag),
        .negative_flag_N_OUT(n_flag),
        .zero_flag_Z_OUT(z_flag),
        .bus_DB_in(db_in),
        .reset_short_counter_TRES1(tres1),
        .reset_counters_TRESX(tresx),
        .shift_instruction_SHIFT(shift),
        .memory_operation_MemOP(memop),
        .store_cycle_STOR(stor),
        .pc_to_db_PC_DB(pc_db),
        .fetch_opcode_FETCH(fetch),
        .inject_brk_0_IR(zero_ir),
        .output_enable_X_SB(x_sb),
        .output_enable_Y_SB(y_sb),
        .load_SB_X(sb_x),
        .load_SB_Y(sb_y),
        .output_enable_S_SB(s_sb),
        .output_enable_S_ADL(s_adl),
        .load_SB_S(sb_s),
        .refresh_S_S(s_s),
        .load_NDB_ADD(ndb_add),
        .load_DB_ADD(db_add),
        .load_ADL_ADD(adl_add),
        .load_SB_ADD(sb_add),
        .load_0_ADD(zero_add),
        .enable_ands_ANDS(ands),
        .enable_eors_EORS(eors),
        .enable_ors_ORS(ors),
        .enable_srs_SRS(srs),
        .enable_sums_SUMS(sums),
        .carry_in_I_ADDC(i_addc),
        .decimal_add_DAA(daa),
        .decimal_subtract_DSA(dsa),
        .output_enable_ADD_SB_0_6(add_sb06),
        .output_enable_ADD_SB_7(add_sb7),
        .output_enable_ADD_ADL(add_adl),
        .load_SB_AC(sb_ac),
        .output_enable_AC_SB(ac_sb),
        .output_enable_AC_DB(ac_db),
        .increment_pc_I_PC(i_pc),
        .load_PCL_PCL(pcl_pcl),
        .load_ADL_PCL(adl_pcl),
        .output_enable_PCL_ADL(pcl_adl),
        .output_enable_PCL_DB(pcl_db),
        .load_PCH_PCH(pch_pch),
        .load_ADH_PCH(adh_pch),
        .output_enable_PCH_ADH(pch_adh),
        .output_enable_PCH_DB(pch_db),
        .load_ADH_ABH(adh_abh),
        .load_ADL_ABL(adl_abl),
        .connect_SB_DB(sb_db),
        .connect_SB_ADH(sb_adh),
        .clear_0_ADH0(zero_adh0),
        .clear_0_ADH_1_7(zero_adh17),
        .output_enable_DL_DB(dl_db),
        .output_enable_DL_ADL(dl_adl),
        .output_enable_DL_ADH(dl_adh),
        .output_enable_P_DB(p_db),
        .load_DB0_C(db0_c),
        .load_IR5_C(ir5_c),
        .load_ACR_C(acr_c),
        .load_DB1_Z(db1_z),
        .load_DBZ_Z(dbz_z),
        .load_DB2_I(db2_i),
        .load_IR5_I(ir5_i),
        .load_DB3_D(db3_d),
        .load_IR5_D(ir5_d),
        .load_DB6_V(db6_v),
        .load_AVR_V(avr_v),
        .clear_0_V(zero_v),
        .load_DB7_N(db7_n),
        .metaclock(metaclock)
    );

    // The commands cut off during Phi2
    wire [17:0] f_cut_off = {x_sb, y_sb, sb_x, sb_y, sb_s, s_s,
        ndb_add, db_add, adl_add, sb_add, zero_add,
        sb_ac, ac_sb, ac_db, pcl_pcl, adl_pcl, pch_pch, adh_pch};
    // The commands from a latch loaded during Phi2, and not cut off
    wire [28:0] f_phi2_latched = {s_sb, s_adl, add_sb06, add_sb7, add_adl,
        pcl_adl, pcl_db, pch_adh, pch_db,
        adh_abh, adl_abl, sb_db, sb_adh, zero_adh0, zero_adh17, dl_db, dl_adl, dl_adh,
        p_db, db0_c, ir5_c, acr_c, dbz_z, ir5_i, ir5_d, db6_v, avr_v, zero_v, db7_n};
    // The commands from a latch loaded during Phi1
    wire [8:0] f_phi1_latched = {ands, eors, ors, srs, sums, i_addc, daa, dsa, i_pc};

    // The output latches power up clear. The ALU operation and the B input
    // select only hold a valid encoding once they have been loaded: during
    // Phi2, then (the operation) during Phi1.
    reg f_past_valid = 1'b0;
    reg f_loaded_phi2 = 1'b0;
    reg f_loaded_phi1 = 1'b0;
    always @(posedge metaclock) begin
        f_past_valid <= 1'b1;
        if (phi2) f_loaded_phi2 <= 1'b1;
        if (phi1) f_loaded_phi1 <= f_loaded_phi2;
    end

    always @* begin
        if (phi2) begin
            check_cut_off: assert (f_cut_off == 18'b0);
        end else begin
            check_sb_add_or_0_add: assert (sb_add != zero_add);
            check_adl_pcl_or_pcl_pcl: assert (adl_pcl != pcl_pcl);
            check_adh_pch_or_pch_pch: assert (adh_pch != pch_pch);
            check_sb_s_or_s_s: assert (sb_s != s_s);
            if (f_loaded_phi2) begin
                check_db_add_default: assert (db_add == !(ndb_add || adl_add));
            end
        end
        if (f_loaded_phi1) begin
            check_sums_default: assert (sums == !(ands || eors || ors || srs));
        end
        // ROR can hold bit 7 back from SB, but never bits 0-6
        check_add_sb7: assert (!add_sb7 || add_sb06);

        check_shift: assert (shift == (decoder_in[106] || decoder_in[107]));
        check_memop: assert (memop == (decoder_in[111] || decoder_in[122]
            || decoder_in[123] || decoder_in[124] || decoder_in[125]));
        check_stor: assert (stor == (memop && decoder_in[97]));
        check_fetch_ready: assert (!fetch || ready);
        check_zero_ir: assert (zero_ir == !(fetch && b_out));
        check_brk6e_restarts: assert (!brk6e || tresx);
    end

    always @(posedge metaclock) begin
        if (f_past_valid) begin
            if (!$past(phi2)) begin
                check_phi2_latched: assert (f_phi2_latched == $past(f_phi2_latched));
                if (phi2 == $past(phi2)) begin
                    check_cut_off_latched: assert (f_cut_off == $past(f_cut_off));
                end
            end
            if (!$past(phi1)) begin
                check_phi1_latched: assert (f_phi1_latched == $past(f_phi1_latched));
            end
            // A reset, latched during Phi2, restarts the counters
            if ($past(resp) && $past(phi2)) begin
                check_reset_restarts: assert (tresx);
            end

            reach_sums: cover (!phi2 && sums && sb_add && db_add);
            reach_ror_hold: cover (add_sb06 && !add_sb7);
            reach_fetch: cover (fetch && !zero_ir);
            reach_i_pc: cover (i_pc);
            reach_tres1: cover (tres1 && !resp);
            reach_two_ops: cover (ors && ands);
        end
    end
endmodule
