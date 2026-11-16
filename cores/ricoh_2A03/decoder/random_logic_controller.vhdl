library ieee;
use ieee.std_logic_1164.all;

--! @file
--! @brief Random logic and dispatch controller for the Ricoh 2A03
--! @details Turns the @ref Ricoh_2A03_Decoder_Lines "decoder lines" into the
--! control commands that drive the datapath, ALU, program counter and flags,
--! and runs the dispatch logic that sequences each instruction.
--!
--! On the real chip this logic is scattered across the top of the die, between
--! the decoder and the datapath, which is why it's called "random". It is
--! modeled as one entity here, because its parts are tightly coupled: nearly
--! every part takes intermediate signals from the others. It is made of these
--! circuits:
--!
--! - The dispatcher's intermediate signals: `STORE` (decoder line 97),
--!   @ref Ricoh_2A03_Signal_SHIFT, @ref Ricoh_2A03_Signal_MemOP,
--!   @ref Ricoh_2A03_Signal_STOR, `REST`, `BR2` (line 80), `BR3` (line 93) and
--!   `BR0` (line 73, already gated by @ref Ricoh_2A03_Signal_PRDY).
--! - The ACR latch, which holds the ALU carry (`ACRL1`, `ACRL2`) while the
--!   CPU isn't ready.
--! - Instruction completion. `ENDS` ends short instructions (at T0, or BR2 of
--!   a branch that isn't taken), and `ENDX` ends long ones. They make
--!   @ref Ricoh_2A03_Signal_TRES1 and @ref Ricoh_2A03_Signal_TRESX, which reset
--!   the @ref timing_generator. `BRA` ends a branch at BR3 when it didn't
--!   cross a page.
--! - The PC increment logic, @ref Ricoh_2A03_Signal_I_PC, and the opcode fetch
--!   logic, @ref Ricoh_2A03_Signal_FETCH and @ref Ricoh_2A03_Signal_0_IR.
--! - The branch logic: whether a branch is taken (`BRTAKEN`, from the flag
--!   that IR6 and IR7 select, compared to IR5), and its direction (`BRFW`,
--!   from bit 7 of the offset on DB).
--! - Register control: X, Y and S to and from the SB and ADL buses.
--! - ALU control: the ALU inputs, operation, carry-in, BCD correction, and
--!   where its result goes. The ROR circuit holds back `ADD/SB7`, so the
--!   precharged SB7 rotates the carry into bit 7.
--! - PC control: PCL and PCH to and from the ADL, ADH and DB buses.
--! - Bus control: the address bus registers, the accumulator, the bus pass
--!   MOSFETs, the constant generators and the data input latch.
--! - Flags control: loading the P register from DB, IR5, ACR and AVR.
--!
--! Most commands come from an output latch that is loaded during Phi2, from
--! the decoder lines of the current cycle, and so drive the datapath through
--! the next Phi1. Some are cut off during Phi2 as well (see
--! @ref Ricoh_2A03_Signals), since that's when the buses precharge: the
--! register and accumulator commands (except `S/SB` and `S/ADL`), the ALU
--! input loads and the PC select register loads.
--!
--! `0/IR` is asserted whenever `FETCH` isn't, as on the real chip, so the
--! predecode logic sees BRK, and so neither @ref Ricoh_2A03_Signal_TWOCYCLE
--! nor @ref Ricoh_2A03_Signal_IMPLIED, outside the opcode fetch. Without
--! that, an operand byte that looks like a two-cycle opcode would start `T0`.
--!
--! The Verilog model differs from the wiki's transistor-level schematics in
--! one place: its `ADH/ABH` uses the complement of the `INC_SB` group (which
--! loads ABH on nearly every cycle) instead of the `IND`/`T2`/`#PCH/PCH`/`JSR/5`
--! group, which the Verilog computes but never uses. This core follows the
--! schematics. The `BRFW` latch in the Verilog
--! holds bit 7 of the offset, which is set for a backward branch. This core
--! stores its complement, so `BRFW` is set for a forward branch, as its name
--! says.
--!
--! The real chip uses many active-low signals (`/ready`, `#TRESX`, `/BRTAKEN`,
--! `#1/PC`, `/ACIN`, `/DAA`, `/DSA` and so on), and stores most latches
--! inverted. This core keeps every signal active-high, like the rest of its
--! control signals. Several circuits keep their own latch of `ready` during
--! Phi1, which all hold the same value, so this core keeps only one. Lines 83,
--! 90 and 128 already exclude push/pull (line 129) in the @ref decoder_rom.
--!
--! Every latch is sampled on the @ref metaclock while its phase is high, like
--! the other registers in this core. Each signal below stores the active-high
--! value. Where a latch feeds another latch of the same phase through logic,
--! the second one settles a metaclock later, as it would on the real chip
--! while both latches are open.

--! Random logic and dispatch, making every control command from the decoder
entity random_logic_controller is
    port(
        --! @ref Ricoh_2A03_Phi1
        phi1: in std_ulogic;
        --! @ref Ricoh_2A03_Phi2
        phi2: in std_ulogic;

        -- Inputs from the rest of the decoder

        --! The @ref Ricoh_2A03_Decoder_Lines "decoder lines", from
        --! @ref decoder_rom
        decoder_in: in std_ulogic_vector(129 downto 0);
        --! @ref Ricoh_2A03_Signal_ready
        ready: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_ReadyPhi1
        ready_phi1_ReadyPhi1: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_T0
        cycle_T0: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_T1
        cycle_T1: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_T6
        rmw_cycle_T6: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_T7
        rmw_cycle_T7: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_IMPLIED, from @ref predecode_logic
        single_byte_IMPLIED: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_IR5, bit 5 of the opcode
        instruction_IR5: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_RESP
        reset_pending_RESP: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_BRK6E
        brk_cycle_6_end_BRK6E: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_B_OUT
        break_flag_B_OUT: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_0_ADL0, from @ref interrupt_controller
        vector_0_ADL0: in std_ulogic;

        -- Inputs from the datapath and ALU

        --! @ref Ricoh2A03_ALU_ACR
        alu_carry_ACR: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_C_OUT
        carry_flag_C_OUT: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_D_OUT
        decimal_flag_D_OUT: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_V_OUT
        overflow_flag_V_OUT: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_N_OUT
        negative_flag_N_OUT: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_Z_OUT
        zero_flag_Z_OUT: in std_ulogic;
        --! @ref Ricoh_2A03_DB, as resolved by @ref bus_multiplexer. Only bit
        --! 7 (the branch direction) is used.
        bus_DB_in: in std_ulogic_vector(7 downto 0);

        -- Dispatch

        --! @ref Ricoh_2A03_Signal_TRES1
        reset_short_counter_TRES1: out std_ulogic;
        --! @ref Ricoh_2A03_Signal_TRESX
        reset_counters_TRESX: out std_ulogic;
        --! @ref Ricoh_2A03_Signal_SHIFT
        shift_instruction_SHIFT: out std_ulogic;
        --! @ref Ricoh_2A03_Signal_MemOP
        memory_operation_MemOP: out std_ulogic;
        --! @ref Ricoh_2A03_Signal_STOR
        store_cycle_STOR: out std_ulogic;
        --! @ref Ricoh_2A03_Signal_PC_DB
        pc_to_db_PC_DB: out std_ulogic;
        --! @ref Ricoh_2A03_Signal_FETCH
        fetch_opcode_FETCH: out std_ulogic;
        --! @ref Ricoh_2A03_Signal_0_IR
        inject_brk_0_IR: out std_ulogic;

        -- Register control

        --! @ref Ricoh_Signal_X_SB
        output_enable_X_SB: out std_ulogic;
        --! @ref Ricoh_Signal_Y_SB
        output_enable_Y_SB: out std_ulogic;
        --! @ref Ricoh_Signal_SB_X
        load_SB_X: out std_ulogic;
        --! @ref Ricoh_Signal_SB_Y
        load_SB_Y: out std_ulogic;
        --! @ref Ricoh_2A03_Signal_S_SB
        output_enable_S_SB: out std_ulogic;
        --! @ref Ricoh_2A03_Signal_S_ADL
        output_enable_S_ADL: out std_ulogic;
        --! @ref Ricoh_2A03_Signal_SB_S
        load_SB_S: out std_ulogic;
        --! @ref Ricoh_2A03_Signal_S_S
        refresh_S_S: out std_ulogic;

        -- ALU control

        --! @ref Ricoh_2A03_Signal_NOT_DB_ADD
        load_NDB_ADD: out std_ulogic;
        --! @ref Ricoh_2A03_Signal_DB_ADD
        load_DB_ADD: out std_ulogic;
        --! @ref Ricoh_2A03_Signal_ADL_ADD
        load_ADL_ADD: out std_ulogic;
        --! @ref Ricoh2A03_SB_ADD
        load_SB_ADD: out std_ulogic;
        --! @ref Ricoh2A03_0_ADD
        load_0_ADD: out std_ulogic;
        --! @ref Ricoh2A03_ALU_ANDS
        enable_ands_ANDS: out std_ulogic;
        --! @ref Ricoh2A03_ALU_EORS
        enable_eors_EORS: out std_ulogic;
        --! @ref Ricoh2A03_ALU_ORS
        enable_ors_ORS: out std_ulogic;
        --! @ref Ricoh2A03_ALU_SRS
        enable_srs_SRS: out std_ulogic;
        --! @ref Ricoh2A03_ALU_SUMS
        enable_sums_SUMS: out std_ulogic;
        --! @ref Ricoh2A03_ALU_IADDC
        carry_in_I_ADDC: out std_ulogic;
        --! @ref Ricoh2A03_ALU_DAA
        decimal_add_DAA: out std_ulogic;
        --! @ref Ricoh2A03_DSA
        decimal_subtract_DSA: out std_ulogic;
        --! @ref Ricoh2A03_ADD_SB_0_6
        output_enable_ADD_SB_0_6: out std_ulogic;
        --! @ref Ricoh2A03_ADD_SB_7
        output_enable_ADD_SB_7: out std_ulogic;
        --! @ref Ricoh2A03_ADD_ADL
        output_enable_ADD_ADL: out std_ulogic;

        -- Accumulator control

        --! @ref Ricoh_Signal_SB_AC
        load_SB_AC: out std_ulogic;
        --! @ref Ricoh_Signal_AC_SB
        output_enable_AC_SB: out std_ulogic;
        --! @ref Ricoh_Signal_AC_DB
        output_enable_AC_DB: out std_ulogic;

        -- Program counter control

        --! @ref Ricoh_2A03_Signal_I_PC
        increment_pc_I_PC: out std_ulogic;
        --! @ref Ricoh_2A03_Signal_PCL_PCL
        load_PCL_PCL: out std_ulogic;
        --! @ref Ricoh_2A03_Signal_ADL_PCL
        load_ADL_PCL: out std_ulogic;
        --! @ref Ricoh_2A03_Signal_PCL_ADL
        output_enable_PCL_ADL: out std_ulogic;
        --! @ref Ricoh_2A03_Signal_PCL_DB
        output_enable_PCL_DB: out std_ulogic;
        --! @ref Ricoh_2A03_Signal_PCH_PCH
        load_PCH_PCH: out std_ulogic;
        --! @ref Ricoh_2A03_Signal_ADH_PCH
        load_ADH_PCH: out std_ulogic;
        --! @ref Ricoh_2A03_Signal_PCH_ADH
        output_enable_PCH_ADH: out std_ulogic;
        --! @ref Ricoh_2A03_Signal_PCH_DB
        output_enable_PCH_DB: out std_ulogic;

        -- Bus control

        --! @ref Ricoh_2A03_Signal_ADH_ABH
        load_ADH_ABH: out std_ulogic;
        --! @ref Ricoh_2A03_Signal_ADL_ABL
        load_ADL_ABL: out std_ulogic;
        --! @ref Ricoh_2A03_Signal_SB_DB
        connect_SB_DB: out std_ulogic;
        --! @ref Ricoh_2A03_Signal_SB_ADH
        connect_SB_ADH: out std_ulogic;
        --! @ref Ricoh_2A03_Signal_0_ADH0
        clear_0_ADH0: out std_ulogic;
        --! @ref Ricoh_2A03_Signal_0_ADH_1_7
        clear_0_ADH_1_7: out std_ulogic;
        --! @ref Ricoh_2A03_Signal_DL_DB
        output_enable_DL_DB: out std_ulogic;
        --! @ref Ricoh_2A03_Signal_DL_ADL
        output_enable_DL_ADL: out std_ulogic;
        --! @ref Ricoh_2A03_Signal_DL_ADH
        output_enable_DL_ADH: out std_ulogic;

        -- Flags control

        --! @ref Ricoh_Signal_P_DB
        output_enable_P_DB: out std_ulogic;
        --! @ref Ricoh_Signal_DB0_C
        load_DB0_C: out std_ulogic;
        --! @ref Ricoh_Signal_IR5_C
        load_IR5_C: out std_ulogic;
        --! @ref Ricoh_Signal_ACR_C
        load_ACR_C: out std_ulogic;
        --! @ref Ricoh_Signal_DB1_Z
        load_DB1_Z: out std_ulogic;
        --! @ref Ricoh_Signal_DBZ_Z
        load_DBZ_Z: out std_ulogic;
        --! @ref Ricoh_Signal_DB2_I
        load_DB2_I: out std_ulogic;
        --! @ref Ricoh_Signal_IR5_I
        load_IR5_I: out std_ulogic;
        --! @ref Ricoh_Signal_DB3_D
        load_DB3_D: out std_ulogic;
        --! @ref Ricoh_Signal_IR5_D
        load_IR5_D: out std_ulogic;
        --! @ref Ricoh_Signal_DB6_V
        load_DB6_V: out std_ulogic;
        --! @ref Ricoh_Signal_AVR_V
        load_AVR_V: out std_ulogic;
        --! @ref Ricoh_Signal_0_V
        clear_0_V: out std_ulogic;
        --! @ref Ricoh_Signal_DB7_N
        load_DB7_N: out std_ulogic;

        --! Clock to drive the latch circuitry
        --! @ref metaclock
        metaclock: in std_ulogic
    );
end entity random_logic_controller;

architecture rtl of random_logic_controller is
    alias X: std_ulogic_vector(129 downto 0) is decoder_in;

    -- Shared

    --! `nready_latch` (Phi1): `ready`. Each of the short cycle counter, the
    --! register, ALU (ROR), PC and bus control has its own copy.
    signal ready_phi1_latch: std_ulogic := '1';

    -- ACR latch

    --! `acr_latch1` (Phi1): `ACRL1`
    signal acr_latch1: std_ulogic := '0';
    --! `acr_latch2` (Phi2): `ACRL1` from Phi1, which is `ACRL2`
    signal acr_latch2: std_ulogic := '0';

    -- Short cycle counter (TRES1)

    --! `step_latch1` (Phi2): the last Phi1 wasn't ready, `step_latch2` is
    --! clear, and no reset
    signal step_latch1: std_ulogic := '0';
    --! `step_latch2` (Phi1): neither `step_latch1` nor `BRA`
    signal step_latch2: std_ulogic := '1';

    -- Instruction completion

    --! `tresx_latch1` (Phi2): decoder line 91 or 92
    signal tresx_latch1: std_ulogic := '0';
    --! `tresx_latch2` (Phi2): `RESP`, `ENDS` or `ENDX` while ready
    signal tresx_latch2: std_ulogic := '0';
    --! `ends_latch1` (Phi2): a short instruction is ending: T0, or BR2 of a
    --! branch that isn't taken, while ready, or T1 while not ready
    signal ends_latch1: std_ulogic := '0';
    --! `ends_latch2` (Phi2): `RESP`
    signal ends_latch2: std_ulogic := '0';

    -- PC increment

    --! `br_latch1` (Phi2): PCL goes through ADL outside a branch, or a branch
    --! isn't taken at BR2, so PC increments
    signal br_latch1: std_ulogic := '0';
    --! `br_latch2` (Phi2): BR3 while `ReadyPhi1`
    signal br3_latch: std_ulogic := '0';
    --! `ipc_latch1` (Phi1): `B_OUT`
    signal ipc_latch1: std_ulogic := '1';
    --! `ipc_latch2` (Phi1): `BRA`
    signal ipc_latch2: std_ulogic := '0';
    --! `ipc_latch3` (Phi1): increment, outside a branch or implied opcode
    signal ipc_latch3: std_ulogic := '0';

    -- Opcode fetch

    --! `fetch_latch` (Phi2): `T1`
    signal fetch_latch: std_ulogic := '0';

    -- Branch logic

    --! `br2_latch` (Phi2): BR2
    signal br2_latch: std_ulogic := '0';
    --! `brfw_latch1` (Phi1): `BRFW`, bit 7 of the offset (inverted) at BR2
    signal brfw_latch1: std_ulogic := '0';
    --! `brfw_latch2` (Phi2): `BRFW` from Phi1, so it holds after BR2
    signal brfw_latch2: std_ulogic := '0';

    -- Register control output latches (Phi2)

    signal xsb_latch: std_ulogic := '0';
    signal ysb_latch: std_ulogic := '0';
    signal sbx_latch: std_ulogic := '0';
    signal sby_latch: std_ulogic := '0';
    signal ssb_latch: std_ulogic := '0';
    signal sadl_latch: std_ulogic := '0';
    --! `sbs_latch` and `ss_latch`, which hold complements: `SB/S`
    signal sbs_latch: std_ulogic := '0';

    -- ALU control

    --! `acin_latch1`-`acin_latch4` (Phi2): the sources of the carry-in
    signal acin_latch: std_ulogic_vector(4 downto 1) := (others => '0');
    --! `acin_latch5` (Phi1): any of the carry-in sources, which is `I/ADDC`
    signal acin_latch5: std_ulogic := '0';
    signal ndbadd_latch: std_ulogic := '0';
    --! `dbadd_latch` (Phi2): neither `NDB/ADD` nor `ADL/ADD`
    signal dbadd_latch: std_ulogic := '0';
    signal adladd_latch: std_ulogic := '0';
    --! `zadd_latch` and `sbadd_latch`, which hold complements: `0/ADD`
    signal zadd_latch: std_ulogic := '0';
    --! `ands_latch1`, `eors_latch1`, `ors_latch1`, `srs_latch1`,
    --! `sums_latch1` (Phi2): the operation
    signal op_latch1: std_ulogic_vector(4 downto 0) := (others => '0');
    --! `ands_latch2` ... `sums_latch2` (Phi1): the operation from Phi2
    signal op_latch2: std_ulogic_vector(4 downto 0) := (others => '0');
    --! `daa_latch1`, `dsa_latch1` (Phi2), then `daa_latch2`, `dsa_latch2`
    --! (Phi1): BCD correction after addition or subtraction
    signal daa_latch1: std_ulogic := '0';
    signal daa_latch2: std_ulogic := '0';
    signal dsa_latch1: std_ulogic := '0';
    signal dsa_latch2: std_ulogic := '0';
    signal addsb06_latch: std_ulogic := '0';
    signal addsb7_latch: std_ulogic := '0';
    signal addadl_latch: std_ulogic := '0';

    -- ROR

    --! `cout_latch` (Phi2): the C flag
    signal ror_carry_latch: std_ulogic := '0';
    --! `mux_latch1` (Phi2): a shift right, while ready during Phi1
    signal ror_mux_latch: std_ulogic := '0';
    --! `ff_latch1` (Phi1): the C flag from the start of the shift
    signal ror_ff_latch1: std_ulogic := '0';
    --! `ff_latch2` (Phi2): `ff_latch1`, so it holds
    signal ror_ff_latch2: std_ulogic := '0';
    --! `sr_latch1` (Phi2), then `sr_latch2` (Phi1): `SR`
    signal ror_sr_latch1: std_ulogic := '0';
    signal ror_sr_latch2: std_ulogic := '0';

    -- PC control

    --! `pch_db_latch1` (Phi2): `PCH/DB`, to push PCL on the next cycle
    signal pch_db_latch1: std_ulogic := '0';
    --! `pcl_db_latch1` (Phi1): PCH was pushed last cycle, while ready
    signal pcl_db_latch1: std_ulogic := '0';
    signal pcl_db_latch2: std_ulogic := '0';
    signal pch_db_latch2: std_ulogic := '0';
    signal pcl_adl_latch: std_ulogic := '0';
    signal pch_adh_latch: std_ulogic := '0';
    --! `adl_pcl_latch` and `pcl_pcl_latch`, which hold complements: `ADL/PCL`
    signal adl_pcl_latch: std_ulogic := '0';
    --! `adh_pch_latch` and `pch_pch_latch`, which hold complements: `ADH/PCH`
    signal adh_pch_latch: std_ulogic := '0';

    -- Bus control output latches (Phi2)

    signal z_adh0_latch: std_ulogic := '0';
    signal z_adh17_latch: std_ulogic := '0';
    signal sb_ac_latch: std_ulogic := '0';
    signal adl_abl_latch: std_ulogic := '0';
    signal ac_sb_latch: std_ulogic := '0';
    signal sb_db_latch: std_ulogic := '0';
    signal ac_db_latch: std_ulogic := '0';
    signal sb_adh_latch: std_ulogic := '0';
    signal dl_adh_latch: std_ulogic := '0';
    signal dl_adl_latch: std_ulogic := '0';
    signal adh_abh_latch: std_ulogic := '0';
    signal dl_db_latch: std_ulogic := '0';

    -- Flags control output latches (Phi2)

    signal pdb_latch: std_ulogic := '0';
    signal iri_latch: std_ulogic := '0';
    signal irc_latch: std_ulogic := '0';
    signal ird_latch: std_ulogic := '0';
    signal zv_latch: std_ulogic := '0';
    signal acrc_latch: std_ulogic := '0';
    signal dbz_latch: std_ulogic := '0';
    --! `dbn_latch` (Phi2): BIT T1X (decoder line 109)
    signal dbn_latch: std_ulogic := '0';
    signal dbc_latch: std_ulogic := '0';
    --! `pin_latch` (Phi2): PLP or RTI (lines 114, 115) pull P
    signal pin_latch: std_ulogic := '0';
    --! `bit_latch` (Phi2): BIT T0 (decoder line 113)
    signal bit_latch: std_ulogic := '0';
    --! `avr_latch` (Phi2): ADC or SBC T1X (decoder line 112)
    signal avr_latch: std_ulogic := '0';

    -- Dispatch intermediate signals
    signal STORE: std_ulogic;
    signal SHIFT: std_ulogic;
    signal MemOP: std_ulogic;
    signal STOR: std_ulogic;
    --! Shift or store: these don't end early at lines 91 and 92
    signal REST: std_ulogic;
    signal BR0: std_ulogic;
    signal BR2: std_ulogic;
    signal BR3: std_ulogic;

    signal ACRL1: std_ulogic;
    signal ACRL2: std_ulogic;
    signal ENDS: std_ulogic;
    --! Ends a long instruction. The chip's `ENDX` net is the complement.
    signal ENDX: std_ulogic;
    --! A branch at BR3 that didn't cross a page, which ends it
    signal BRA: std_ulogic;
    signal TRES1: std_ulogic;
    signal TRESX: std_ulogic;
    signal FETCH: std_ulogic;

    signal BRFW: std_ulogic;
    --! The flag that IR6 and IR7 select for a branch
    signal branch_flag: std_ulogic;
    signal BRTAKEN: std_ulogic;

    -- Register control intermediate signals
    signal X_SB: std_ulogic;
    signal Y_SB: std_ulogic;
    signal SB_X: std_ulogic;
    signal SB_Y: std_ulogic;
    signal SB_S: std_ulogic;
    signal S_ADL: std_ulogic;
    --! Store X or Y. The chip's `STXY` net is the complement.
    signal STXY: std_ulogic;
    --! SB to X or Y. The chip calls it `#SBXY`, but it is active-high.
    signal SBXY: std_ulogic;
    signal STKOP: std_ulogic;

    -- ALU control intermediate signals
    signal SBC0: std_ulogic;
    --! Branch: carry-in and `NDB/ADD`, to fix up PCH
    signal BRX: std_ulogic;
    signal CSET: std_ulogic;
    signal op_OR: std_ulogic;
    signal op_AND: std_ulogic;
    signal op_EOR: std_ulogic;
    signal SR: std_ulogic;
    signal NOADL: std_ulogic;
    signal INC_SB: std_ulogic;
    signal ZERO_ADD: std_ulogic;
    signal NDB_ADD: std_ulogic;
    signal ADL_ADD: std_ulogic;
    signal ADD_SB06: std_ulogic;
    --! The ROR circuit holds back `ADD/SB7`. The chip's `nADDSB7`.
    signal ror_hold_SB7: std_ulogic;

    -- PC control intermediate signals
    --! BRK, RTI, JSR or JMP. The chip's `JB` net is the complement.
    signal JB: std_ulogic;
    signal PCH_DB: std_ulogic;
    signal PCL_ADL: std_ulogic;
    signal ADL_PCL: std_ulogic;
    --! `ADH/PCH`, which is also the chip's `#PCH/PCH` net
    signal ADH_PCH: std_ulogic;
    signal DL_PCH: std_ulogic;
    signal PC_DB: std_ulogic;

    -- Bus control intermediate signals
    signal DL_ADL: std_ulogic;
    signal SB_AC: std_ulogic;
    signal ZTST: std_ulogic;
    signal JSXY: std_ulogic;
    signal IND: std_ulogic;
    signal PGX: std_ulogic;
    signal SB_ADH: std_ulogic;
    signal SBA: std_ulogic;
    signal ADH_ABH: std_ulogic;
    signal DL_DB: std_ulogic;
    signal AC_SB: std_ulogic;
    signal AC_DB: std_ulogic;
    signal SB_DB: std_ulogic;
    signal ADL_ABL: std_ulogic;

    -- Flags control intermediate signals
    signal ARIT: std_ulogic;
    signal PIN: std_ulogic;
    signal DB_P: std_ulogic;
begin
    ---------------------------------------------------------------------------
    -- Dispatch
    ---------------------------------------------------------------------------

    STORE <= X(97);
    SHIFT <= X(106) or X(107);
    MemOP <= X(111) or X(122) or X(123) or X(124) or X(125);
    STOR <= MemOP and STORE;
    REST <= SHIFT or STORE;
    BR0 <= X(73);
    BR2 <= X(80);
    BR3 <= X(93);

    -- The ACR latch follows ACR while ready during Phi1, and holds otherwise
    ACRL1 <= alu_carry_ACR when ready_phi1_ReadyPhi1 = '1' else ACRL2;
    ACRL2 <= acr_latch2;

    -- A short instruction ends at T0, or at BR2 if the branch isn't taken
    ENDS <= ends_latch1 and not ends_latch2;
    ENDX <= (not X(96) and not SHIFT and MemOP) or rmw_cycle_T7
        or X(100) or X(101) or X(102) or X(103) or X(104) or X(105) or BR3;
    TRESX <= (not ACRL1 and tresx_latch1 and ready and not REST)
        or brk_cycle_6_end_BRK6E or tresx_latch2;

    BRA <= (BRFW xor alu_carry_ACR) and br3_latch;
    TRES1 <= ((step_latch1 or BRA) and ready) or ENDS;

    FETCH <= fetch_latch and ready;

    ---------------------------------------------------------------------------
    -- Branch logic
    ---------------------------------------------------------------------------

    BRFW <= brfw_latch1;
    -- IR7 IR6: 00 N, 01 V, 10 C, 11 Z. Decoder lines 121 and 126 are /IR6 and
    -- /IR7.
    branch_flag <= (X(121) and X(126) and negative_flag_N_OUT)
        or (not X(121) and X(126) and overflow_flag_V_OUT)
        or (X(121) and not X(126) and carry_flag_C_OUT)
        or (not X(121) and not X(126) and zero_flag_Z_OUT);
    BRTAKEN <= not (branch_flag xor instruction_IR5);

    ---------------------------------------------------------------------------
    -- Register control
    ---------------------------------------------------------------------------

    Y_SB <= X(1) or X(2) or X(3) or X(4) or X(5) or (X(6) and X(7))
        or (X(0) and STOR);
    X_SB <= X(8) or X(9) or X(10) or X(11) or X(13) or (X(6) and not X(7))
        or (X(12) and STOR);
    SB_X <= X(14) or X(15) or X(16);
    SB_Y <= X(18) or X(19) or X(20);
    STKOP <= (X(21) or X(22) or X(23) or X(24) or X(25) or X(26))
        and ready_phi1_latch;
    SB_S <= X(13) or (X(48) and ready) or STKOP;
    S_ADL <= (X(21) and ready_phi1_latch) or X(35);
    STXY <= STOR and (X(0) or X(12));
    SBXY <= SB_X or SB_Y;

    ---------------------------------------------------------------------------
    -- ALU control
    ---------------------------------------------------------------------------

    SBC0 <= X(51);
    BRX <= X(49) or X(50) or (BR3 and BRFW);
    CSET <= (carry_flag_C_OUT and (cycle_T0 or rmw_cycle_T6)
        and (X(52) or X(53))) or X(54);
    op_OR <= X(32) or not ready;
    op_AND <= X(69) or X(70);
    op_EOR <= X(29);
    SR <= X(75) or (X(76) and rmw_cycle_T6);
    NOADL <= not (X(84) or X(85) or X(86) or X(87) or X(88) or X(89) or X(26));
    INC_SB <= X(39) or X(40) or X(41) or X(42) or X(43)
        or (X(44) and rmw_cycle_T6);
    ZERO_ADD <= X(30) or X(31) or X(45) or X(48) or INC_SB or X(47)
        or brk_cycle_6_end_BRK6E or not ready;
    NDB_ADD <= (BRX or X(56) or SBC0) and ready;
    ADL_ADD <= (X(33) and not X(34)) or X(35) or X(36) or X(37) or X(38)
        or X(39) or not ready;
    ADD_SB06 <= STKOP or X(56) or PGX or cycle_T1 or rmw_cycle_T7;
    ror_hold_SB7 <= X(27) and ror_ff_latch1 and ror_sr_latch2;

    ---------------------------------------------------------------------------
    -- PC control
    ---------------------------------------------------------------------------

    JB <= X(94) or X(95) or X(96);
    PCH_DB <= X(77) or X(78);
    PCL_ADL <= cycle_T1 or X(56) or X(83) or BR2
        or (cycle_T0 and not (JB and ready_phi1_latch));
    ADL_PCL <= PCL_ADL or X(84) or cycle_T0 or (BR3 and ready_phi1_latch);
    ADH_PCH <= X(84) or X(83) or cycle_T0 or cycle_T1 or BR2 or BR3;
    DL_PCH <= cycle_T0 and JB;
    PC_DB <= pcl_db_latch1 or PCH_DB;

    ---------------------------------------------------------------------------
    -- Bus control
    ---------------------------------------------------------------------------

    DL_ADL <= X(81) or X(82);
    SB_AC <= X(58) or X(59) or X(60) or X(61) or X(62) or X(63) or X(64);
    ZTST <= SBXY or SB_AC or rmw_cycle_T7 or op_AND;
    JSXY <= X(48) or STXY;
    IND <= X(89) or X(90) or X(91) or X(84);
    PGX <= X(71) or X(72) or BR0;
    SB_ADH <= PGX or BR3;
    SBA <= SB_ADH and ACRL2 and ready_phi1_latch;
    ADH_ABH <= vector_0_ADL0 or (not BR3 and (SBA
        or (ready and (IND or X(28) or ADH_PCH or X(56)))));
    DL_DB <= BR2 or ((X(83) or cycle_T0) and not X(128))
        or INC_SB or X(45) or brk_cycle_6_end_BRK6E or X(46) or X(47) or X(48)
        or X(101) or rmw_cycle_T6;
    AC_DB <= X(74) or (X(79) and STOR);
    AC_SB <= (X(65) and not X(64)) or X(66) or X(67) or X(68) or op_AND;
    SB_DB <= (rmw_cycle_T6 and X(55)) or (ZTST and not op_AND) or X(67)
        or cycle_T1 or BR2 or JSXY;
    ADL_ABL <= not rmw_cycle_T6 and not rmw_cycle_T7 and not X(71)
        and not X(72) and ready;

    ---------------------------------------------------------------------------
    -- Flags control
    ---------------------------------------------------------------------------

    ARIT <= (X(107) and rmw_cycle_T7) or X(112) or X(116) or X(117) or X(118)
        or X(119);
    PIN <= X(114) or X(115);
    DB_P <= pin_latch and ready;

    process(metaclock)
    begin
        if rising_edge(metaclock) then
            if phi1 = '1' then
                ready_phi1_latch <= ready;

                acr_latch1 <= ACRL1;

                step_latch2 <= not (step_latch1 or BRA);

                ipc_latch1 <= break_flag_B_OUT;
                ipc_latch2 <= BRA;
                ipc_latch3 <= ready and br_latch1 and not single_byte_IMPLIED;

                -- Bit 7 of the offset is clear for a forward branch
                brfw_latch1 <= (br2_latch and not bus_DB_in(7))
                    or (not br2_latch and brfw_latch2);

                acin_latch5 <= acin_latch(1) or acin_latch(2) or acin_latch(3)
                    or acin_latch(4);
                op_latch2 <= op_latch1;
                daa_latch2 <= daa_latch1;
                dsa_latch2 <= dsa_latch1;

                if ror_mux_latch = '1' then
                    ror_ff_latch1 <= ror_carry_latch;
                else
                    ror_ff_latch1 <= ror_ff_latch2;
                end if;
                ror_sr_latch2 <= ror_sr_latch1;

                pcl_db_latch1 <= pch_db_latch1 and ready;
            end if;

            if phi2 = '1' then
                acr_latch2 <= acr_latch1;

                step_latch1 <= not (reset_pending_RESP or ready_phi1_latch
                    or step_latch2);

                tresx_latch1 <= X(91) or X(92);
                tresx_latch2 <= reset_pending_RESP or ENDS or (ready and ENDX);
                if ready = '1' then
                    ends_latch1 <= cycle_T0 or (not BRTAKEN and BR2);
                else
                    ends_latch1 <= cycle_T1;
                end if;
                ends_latch2 <= reset_pending_RESP;

                br3_latch <= BR3 and ready_phi1_ReadyPhi1;
                br_latch1 <= (ADL_PCL and not BR2 and not BR3)
                    or (not BRTAKEN and BR2);

                fetch_latch <= cycle_T1;

                br2_latch <= BR2;
                brfw_latch2 <= brfw_latch1;

                xsb_latch <= X_SB;
                ysb_latch <= Y_SB;
                sbx_latch <= SB_X;
                sby_latch <= SB_Y;
                ssb_latch <= X(17);
                sadl_latch <= S_ADL;
                sbs_latch <= SB_S;

                acin_latch(1) <= ADL_ADD and X(47);
                acin_latch(2) <= INC_SB;
                acin_latch(3) <= BRX;
                acin_latch(4) <= CSET;
                ndbadd_latch <= NDB_ADD;
                dbadd_latch <= not NDB_ADD and not ADL_ADD;
                adladd_latch <= ADL_ADD;
                zadd_latch <= ZERO_ADD;
                op_latch1 <= (op_AND, op_EOR, op_OR, SR,
                    not (op_AND or op_EOR or op_OR or SR));
                daa_latch1 <= X(52) and decimal_flag_D_OUT and not SBC0;
                dsa_latch1 <= decimal_flag_D_OUT and SBC0;
                addsb06_latch <= ADD_SB06;
                addsb7_latch <= ADD_SB06 and not ror_hold_SB7;
                addadl_latch <= not NOADL and not PGX;

                ror_carry_latch <= carry_flag_C_OUT;
                ror_mux_latch <= ready_phi1_latch and SR;
                ror_ff_latch2 <= ror_ff_latch1;
                ror_sr_latch1 <= SR;

                pch_db_latch1 <= PCH_DB;
                pcl_db_latch2 <= pcl_db_latch1;
                pch_db_latch2 <= PCH_DB;
                pcl_adl_latch <= PCL_ADL;
                pch_adh_latch <= (PCL_ADL and not DL_PCH and not BR0) or BR3;
                adl_pcl_latch <= ADL_PCL;
                adh_pch_latch <= ADH_PCH;

                z_adh0_latch <= DL_ADL;
                z_adh17_latch <= X(57) or DL_ADL;
                sb_ac_latch <= SB_AC;
                adl_abl_latch <= ADL_ABL;
                ac_sb_latch <= AC_SB;
                sb_db_latch <= SB_DB;
                ac_db_latch <= AC_DB;
                sb_adh_latch <= SB_ADH;
                dl_adh_latch <= DL_PCH or IND;
                dl_adl_latch <= DL_ADL;
                adh_abh_latch <= ADH_ABH;
                dl_db_latch <= DL_DB;

                pdb_latch <= X(98) or X(99);
                iri_latch <= X(108);
                irc_latch <= X(110);
                ird_latch <= X(120);
                zv_latch <= X(127);
                acrc_latch <= ARIT;
                dbz_latch <= acrc_latch or ZTST or X(109);
                dbn_latch <= X(109);
                dbc_latch <= SR or DB_P;
                pin_latch <= PIN;
                bit_latch <= X(113);
                avr_latch <= X(112);
            end if;
        end if;
    end process;

    -- Dispatch
    reset_short_counter_TRES1 <= TRES1;
    reset_counters_TRESX <= TRESX;
    shift_instruction_SHIFT <= SHIFT;
    memory_operation_MemOP <= MemOP;
    store_cycle_STOR <= STOR;
    pc_to_db_PC_DB <= PC_DB;
    fetch_opcode_FETCH <= FETCH;
    inject_brk_0_IR <= not (FETCH and break_flag_B_OUT);

    -- Register control
    output_enable_X_SB <= xsb_latch and not phi2;
    output_enable_Y_SB <= ysb_latch and not phi2;
    load_SB_X <= sbx_latch and not phi2;
    load_SB_Y <= sby_latch and not phi2;
    output_enable_S_SB <= ssb_latch;
    output_enable_S_ADL <= sadl_latch;
    load_SB_S <= sbs_latch and not phi2;
    refresh_S_S <= not sbs_latch and not phi2;

    -- ALU control
    load_NDB_ADD <= ndbadd_latch and not phi2;
    load_DB_ADD <= dbadd_latch and not phi2;
    load_ADL_ADD <= adladd_latch and not phi2;
    load_SB_ADD <= not zadd_latch and not phi2;
    load_0_ADD <= zadd_latch and not phi2;
    enable_ands_ANDS <= op_latch2(4);
    enable_eors_EORS <= op_latch2(3);
    enable_ors_ORS <= op_latch2(2);
    enable_srs_SRS <= op_latch2(1);
    enable_sums_SUMS <= op_latch2(0);
    carry_in_I_ADDC <= acin_latch5;
    decimal_add_DAA <= daa_latch2;
    decimal_subtract_DSA <= dsa_latch2;
    output_enable_ADD_SB_0_6 <= addsb06_latch;
    output_enable_ADD_SB_7 <= addsb7_latch;
    output_enable_ADD_ADL <= addadl_latch;

    -- Accumulator control
    load_SB_AC <= sb_ac_latch and not phi2;
    output_enable_AC_SB <= ac_sb_latch and not phi2;
    output_enable_AC_DB <= ac_db_latch and not phi2;

    -- Program counter control
    increment_pc_I_PC <= ipc_latch1 and (ipc_latch2 or ipc_latch3);
    load_PCL_PCL <= not adl_pcl_latch and not phi2;
    load_ADL_PCL <= adl_pcl_latch and not phi2;
    output_enable_PCL_ADL <= pcl_adl_latch;
    output_enable_PCL_DB <= pcl_db_latch2;
    load_PCH_PCH <= not adh_pch_latch and not phi2;
    load_ADH_PCH <= adh_pch_latch and not phi2;
    output_enable_PCH_ADH <= pch_adh_latch;
    output_enable_PCH_DB <= pch_db_latch2;

    -- Bus control
    load_ADH_ABH <= adh_abh_latch;
    load_ADL_ABL <= adl_abl_latch;
    connect_SB_DB <= sb_db_latch;
    connect_SB_ADH <= sb_adh_latch;
    clear_0_ADH0 <= z_adh0_latch;
    clear_0_ADH_1_7 <= z_adh17_latch;
    output_enable_DL_DB <= dl_db_latch;
    output_enable_DL_ADL <= dl_adl_latch;
    output_enable_DL_ADH <= dl_adh_latch;

    -- Flags control. The chip's DB/P loads Z, I and D from DB at once.
    output_enable_P_DB <= pdb_latch;
    load_DB0_C <= dbc_latch;
    load_IR5_C <= irc_latch;
    load_ACR_C <= acrc_latch;
    load_DB1_Z <= DB_P;
    load_DBZ_Z <= dbz_latch;
    load_DB2_I <= DB_P;
    load_IR5_I <= iri_latch;
    load_DB3_D <= DB_P;
    load_IR5_D <= ird_latch;
    load_DB6_V <= pin_latch or bit_latch;
    load_AVR_V <= avr_latch;
    clear_0_V <= zv_latch;
    load_DB7_N <= (dbz_latch or pin_latch) and not dbn_latch;
end architecture rtl;
