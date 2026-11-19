// End-to-end properties of the instruction decoder: the predecode stage, the
// instruction register, the timing generator, the decoder ROM, and the ready,
// interrupt and random logic controllers, wired together as in mos_6502.
//
// Unlike the unit proofs, this harness makes its own Phi1 and Phi2, as the
// real clock does: they alternate, never overlap, and each phase lasts anywhere from 3
// metaclock cycles (the fewest clocks.md allows) to 7 (the top level's
// METACLOCKS_PER_PHASE), chosen freely for every phase. The CPU starts with /RES held low for its
// first 3 cycles, as at power-on. The data bus, and so every opcode and
// operand, is free on every metaclock edge. So are the flags, the DB bus
// (branch direction) and the ALU carry (page crossings), except that each
// only changes when its source can: the carry during Phi2, when the ALU's
// latch loads, the flags during Phi1, when the status register loads, and DB
// outside Phi1, when the data latch drives it. Some latches feed others of
// the same phase, which settle a metaclock later, so an input that changed on
// a phase's last edge would split a decision between them, as the real chip
// never does.
//
// Two tasks (the CLEAN parameter):
//
// - clean: after the power-on reset, RDY stays high and no interrupt comes.
//   Every documented opcode takes its documented number of cycles, counted
//   from one opcode fetch (FETCH) to the next, and writes to memory on the
//   documented number of them. A branch takes 2 cycles when it isn't taken,
//   and 3 or 4 when it is. Every opcode except the JAM opcodes finishes
//   within 8 cycles. The instruction register holds the byte the CPU read.
// - free: RDY, /NMI, /IRQ and /RES are free too, except that RDY only changes
//   during Phi1, as the 6502 datasheet requires. The CPU never stalls a write
//   cycle, keeps at most one of T2-T5 set, and NMI is edge-triggered: once
//   its vector has been fetched, another NMI needs /NMI to have gone high
//   (during Phi2) first.
module decoder_formal #(
    parameter CLEAN = 1
) (
    input metaclock,
    input end_phase,

    input [7:0] data_in,
    input rdy,
    input nmi_n,
    input irq_n,
    input res_n,

    input acr,
    input c_flag,
    input d_flag,
    input i_flag,
    input v_flag,
    input n_flag,
    input z_flag,
    input [7:0] db_in
);
    // #region Clocks
    reg phi1 = 1'b1;
    reg phi2 = 1'b0;
    // The metaclock edges so far in this phase, counting this one. A phase
    // can end on any edge from the 3rd to the 7th.
    localparam MIN_PHASE_EDGES = 3'd3;
    localparam MAX_PHASE_EDGES = 3'd7;
    reg [2:0] f_phase_edges = 3'd1;
    wire f_phase_start = f_phase_edges == 3'd1;
    always @(posedge metaclock) begin
        if (f_phase_edges == MAX_PHASE_EDGES
            || (f_phase_edges >= MIN_PHASE_EDGES && end_phase)) begin
            phi1 <= !phi1;
            phi2 <= !phi2;
            f_phase_edges <= 3'd1;
        end else begin
            f_phase_edges <= f_phase_edges + 3'd1;
        end
    end
    wire f_cycle_start = phi1 && f_phase_start;
    // #endregion

    // #region Decoder
    wire [7:0] predecode_value, predecode_opcode, ir;
    wire twocycle, implied, zero_ir, fetch;
    wire t0, t1, t1x, t2, t3, t4, t5, t6, t7;
    wire [129:0] lines;
    wire tres1, tresx, shift, memop, stor, pc_db;
    wire ready, r_not_w, ready_phi1, prdy;
    wire resp, dores, brk6e, b_out, adl0, adl1, adl2;

    predecode_register pd_register (
        .phi2(phi2),
        .data_in(data_in),
        .predecode_out(predecode_value),
        .metaclock(metaclock)
    );
    predecode_logic pd_logic (
        .predecode_in(predecode_value),
        .inject_brk_0_IR(zero_ir),
        .predecode_out(predecode_opcode),
        .short_instruction_TWOCYCLE(twocycle),
        .single_byte_IMPLIED(implied)
    );
    instruction_register ir_register (
        .phi1(phi1),
        .load_opcode_FETCH(fetch),
        .predecode_in(predecode_opcode),
        .instruction_out(ir),
        .metaclock(metaclock)
    );
    timing_generator timing (
        .phi1(phi1),
        .phi2(phi2),
        .ready(ready),
        .reset_short_counter_TRES1(tres1),
        .reset_counters_TRESX(tresx),
        .short_instruction_TWOCYCLE(twocycle),
        .shift_instruction_SHIFT(shift),
        .memory_operation_MemOP(memop),
        .cycle_T0(t0),
        .cycle_T1(t1),
        .cycle_T1X(t1x),
        .cycle_T2(t2),
        .cycle_T3(t3),
        .cycle_T4(t4),
        .cycle_T5(t5),
        .rmw_cycle_T6(t6),
        .rmw_cycle_T7(t7),
        .metaclock(metaclock)
    );
    decoder_rom rom (
        .instruction_in(ir),
        .cycle_T0(t0),
        .cycle_T1X(t1x),
        .cycle_T2(t2),
        .cycle_T3(t3),
        .cycle_T4(t4),
        .cycle_T5(t5),
        .previous_ready_PRDY(prdy),
        .decoder_out(lines)
    );
    ready_controller ready_control (
        .phi1(phi1),
        .phi2(phi2),
        .ready_pin_RDY(rdy),
        .store_cycle_STOR(stor),
        .pc_to_db_PC_DB(pc_db),
        .brk_t4_X98(lines[98]),
        .push_t2_X100(lines[100]),
        .rmw_cycle_T6(t6),
        .rmw_cycle_T7(t7),
        .resetting_DORES(dores),
        .ready(ready),
        .write_cycle_WR(),
        .read_not_write_R_NOT_W(r_not_w),
        .ready_phi1_ReadyPhi1(ready_phi1),
        .previous_ready_PRDY(prdy),
        .metaclock(metaclock)
    );
    interrupt_controller interrupt_control (
        .phi1(phi1),
        .phi2(phi2),
        .nmi_pin_n_NMI(nmi_n),
        .irq_pin_n_IRQ(irq_n),
        .reset_pin_n_RES(res_n),
        .ready(ready),
        .brk_t5_X22(lines[22]),
        .branch_t2_X80(lines[80]),
        .cycle_T0(t0),
        .interrupt_disable_I_OUT(i_flag),
        .reset_pending_RESP(resp),
        .resetting_DORES(dores),
        .brk_cycle_6_end_BRK6E(brk6e),
        .break_flag_B_OUT(b_out),
        .clear_0_ADL0(adl0),
        .clear_0_ADL1(adl1),
        .clear_0_ADL2(adl2),
        .metaclock(metaclock)
    );
    // Only the dispatch outputs matter here. The unit proof checks the
    // commands, and the CPU testbench what they do to the datapath.
    random_logic_controller random_logic (
        .phi1(phi1),
        .phi2(phi2),
        .decoder_in(lines),
        .ready(ready),
        .ready_phi1_ReadyPhi1(ready_phi1),
        .cycle_T0(t0),
        .cycle_T1(t1),
        .rmw_cycle_T6(t6),
        .rmw_cycle_T7(t7),
        .single_byte_IMPLIED(implied),
        .instruction_IR5(ir[5]),
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
        .metaclock(metaclock)
    );
    // #endregion

    // #region Environment
    reg f_past_valid = 1'b0;
    reg f_phi1_was = 1'b0;
    reg f_phi2_was = 1'b0;
    reg f_acr_was = 1'b0;
    reg [5:0] f_flags_was = 6'b0;
    reg f_db7_was = 1'b0;
    reg f_rdy_was = 1'b1;
    wire [5:0] f_flags = {c_flag, d_flag, i_flag, v_flag, n_flag, z_flag};
    // Cycles since power-on, saturating
    reg [1:0] f_power_on_cycles = 2'd0;
    always @(posedge metaclock) begin
        f_past_valid <= 1'b1;
        f_phi1_was <= phi1;
        f_phi2_was <= phi2;
        f_acr_was <= acr;
        f_flags_was <= f_flags;
        f_db7_was <= db_in[7];
        f_rdy_was <= rdy;
        if (f_cycle_start && f_power_on_cycles != 2'd3) begin
            f_power_on_cycles <= f_power_on_cycles + 2'd1;
        end
    end
    wire f_powering_on = f_power_on_cycles != 2'd3;

    always @* begin
        // Each input only changes after an edge of the phase its source
        // loads in (the first step of the next phase included)
        if (f_past_valid && !f_phi2_was) begin
            assume_acr_latched: assume (acr == f_acr_was);
        end
        if (f_past_valid && !f_phi1_was) begin
            assume_flags_latched: assume (f_flags == f_flags_was);
            assume_rdy_phi1: assume (rdy == f_rdy_was);
        end
        if (f_past_valid && f_phi1_was) begin
            assume_db_driven: assume (db_in[7] == f_db7_was);
        end
        if (f_powering_on) begin
            assume_power_on_reset: assume (!res_n);
        end else if (CLEAN) begin
            assume_clean_reset: assume (res_n);
        end
        if (CLEAN) begin
            assume_clean_ready: assume (rdy);
            assume_clean_nmi: assume (nmi_n);
            assume_clean_irq: assume (irq_n);
        end
    end
    // #endregion

    // #region Instruction timing (clean)
    // Each documented opcode's cycles, as 12 bits: the fewest, the most, and
    // how many of them write. Branches take a cycle more when taken, and
    // another when that crosses a page. Indexed reads take a cycle more when
    // they cross a page. 0 for the unofficial opcodes, which aren't checked.
    localparam [3071:0] TIMING = {
        //   x0  x1  x2  x3  x4  x5  x6  x7  x8  x9  xA  xB  xC  xD  xE  xF
        192'h773_660_000_000_000_330_552_000_331_220_220_000_000_440_662_000, // 0x
        192'h240_560_000_000_000_440_662_000_220_450_000_000_000_450_772_000, // 1x
        192'h662_660_000_000_330_330_552_000_440_220_220_000_440_440_662_000, // 2x
        192'h240_560_000_000_000_440_662_000_220_450_000_000_000_450_772_000, // 3x
        192'h660_660_000_000_000_330_552_000_331_220_220_000_330_440_662_000, // 4x
        192'h240_560_000_000_000_440_662_000_220_450_000_000_000_450_772_000, // 5x
        192'h660_660_000_000_000_330_552_000_440_220_220_000_550_440_662_000, // 6x
        192'h240_560_000_000_000_440_662_000_220_450_000_000_000_450_772_000, // 7x
        192'h000_661_000_000_331_331_331_000_220_000_220_000_441_441_441_000, // 8x
        192'h240_661_000_000_441_441_441_000_220_551_220_000_000_551_000_000, // 9x
        192'h220_660_220_000_330_330_330_000_220_220_220_000_440_440_440_000, // Ax
        192'h240_560_000_000_440_440_440_000_220_450_220_000_450_450_450_000, // Bx
        192'h220_660_000_000_330_330_552_000_220_220_220_000_440_440_662_000, // Cx
        192'h240_560_000_000_000_440_662_000_220_450_000_000_000_450_772_000, // Dx
        192'h220_660_000_000_330_330_552_000_220_220_220_000_440_440_662_000, // Ex
        192'h240_560_000_000_000_440_662_000_220_450_000_000_000_450_772_000  // Fx
    };
    // A shift rather than a part-select, which would leave x bits out of range
    wire [11:0] f_timing = TIMING >> ((255 - ir) * 12);
    wire [3:0] f_fewest = f_timing[11:8];
    wire [3:0] f_most = f_timing[7:4];
    wire [3:0] f_writes_expected = f_timing[3:0];
    // A branch (XXX10000) is taken when the flag IR7-IR6 select (N, V, C, Z)
    // equals IR5. It decides during BR2, while the flags hold still.
    wire f_branch = ir[4:0] == 5'b10000;
    wire f_branch_flag = ir[7] ? (ir[6] ? z_flag : c_flag) : (ir[6] ? v_flag : n_flag);
    reg f_taken = 1'b0;
    // The JAM opcodes, which never finish
    wire f_jam = ir[3:0] == 4'h2 && (!ir[7] || ir[4]);

    // Cycles and writes since the last opcode fetch, saturating. A cycle's
    // R/W is latched during Phi1, so it is sampled when Phi2 starts.
    reg [3:0] f_cycles = 4'd0;
    reg [3:0] f_writes = 4'd0;
    // Set from the first opcode fetch after the power-on reset's BRK sequence
    reg f_reset_done = 1'b0;
    reg f_running = 1'b0;
    // The byte the CPU read, latched at the end of each Phi2
    reg [7:0] f_data = 8'b0;
    reg f_fetched = 1'b0;
    always @(posedge metaclock) begin
        if (brk6e) f_reset_done <= 1'b1;
        if (phi2) f_data <= data_in;
        if (phi2 && lines[80]) f_taken <= f_branch_flag == ir[5];
        f_fetched <= f_cycle_start && fetch;
        if (f_cycle_start) begin
            if (fetch) begin
                f_cycles <= 4'd1;
                f_writes <= 4'd0;
                if (f_reset_done) f_running <= 1'b1;
            end else if (f_cycles != 4'hF) begin
                f_cycles <= f_cycles + 4'd1;
            end
        end
        if (phi2 && f_phase_start && !r_not_w && f_writes != 4'hF) begin
            f_writes <= f_writes + 4'd1;
        end
    end

    always @* begin
        if (CLEAN && f_running) begin
            // The opcode in the IR has just finished, as the next one loads
            if (f_cycle_start && fetch && f_timing != 12'b0) begin
                check_cycles: assert (f_cycles >= f_fewest && f_cycles <= f_most);
                check_writes: assert (f_writes == f_writes_expected);
                // Not taken: 2 cycles. Taken: 3, or 4 across a page.
                if (f_branch) begin
                    check_branch: assert (f_taken ? f_cycles >= 4'd3 : f_cycles == 4'd2);
                end
            end
            if (!f_jam) begin
                check_finishes: assert (f_cycles <= 4'd8);
            end
            if (f_fetched) begin
                check_opcode: assert (ir == f_data);
            end
        end
    end
    // #endregion

    // #region Safety (free)
    reg f_nmi_armed = 1'b1;
    reg f_adl2_was = 1'b0;
    always @(posedge metaclock) begin
        f_adl2_was <= adl2;
        if (phi2 && nmi_n) f_nmi_armed <= 1'b1;
        else if (adl2 && !f_adl2_was) f_nmi_armed <= 1'b0;
    end

    always @* begin
        if (!f_powering_on) begin
            // The R/W latch loads during Phi1, so a write is settled in Phi2
            if (phi2 && !f_phase_start && !r_not_w) begin
                check_write_never_stalls: assert (ready);
            end
            check_one_extended_cycle: assert ($onehot0({t2, t3, t4, t5}));
            check_nmi_edge: assert (!(adl2 && !f_adl2_was) || f_nmi_armed);
        end
    end
    // #endregion

    // Each task's covers, since the other's can't happen
    generate
        if (CLEAN) begin : clean_covers
            always @(posedge metaclock) begin
                if (f_running) begin
                    reach_lda_absolute_x_page: cover (f_cycle_start && fetch
                        && ir == 8'hBD && f_cycles == 4'd5);
                    reach_branch_taken_page: cover (f_cycle_start && fetch
                        && ir == 8'hD0 && f_cycles == 4'd4);
                    reach_rmw: cover (f_cycle_start && fetch && ir == 8'hFE
                        && f_writes == 4'd2);
                    reach_jam: cover (f_jam && f_cycles == 4'd9);
                    reach_branch_not_taken: cover (f_cycle_start && fetch
                        && f_branch && !f_taken && f_cycles == 4'd2);
                end
            end
        end else begin : free_covers
            always @(posedge metaclock) begin
                if (!f_powering_on) begin
                    reach_stall: cover (phi2 && !ready && t3);
                    reach_nmi: cover (adl2 && !f_adl2_was);
                    reach_write_with_rdy_low: cover (phi2 && !f_phase_start
                        && !r_not_w && !rdy);
                end
            end
        end
    endgenerate
endmodule
