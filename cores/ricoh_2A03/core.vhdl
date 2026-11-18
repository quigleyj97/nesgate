--! @file core.vhdl
--! @brief The MOS 6502 CPU at the heart of the Ricoh 2A03
--! @details Wires the instruction decoder, the random logic, the ALU
--! (@ref logic_core) and the datapath (@ref mos_6502_datapath) together,
--! following Donald F. Hanson's block diagram of the 6502.
--!
--! - The opcode on the data pins is latched into the @ref predecode_register
--!   during Phi2. The @ref predecode_logic classifies it, and the
--!   @ref instruction_register loads it during the Phi1 that follows, while
--!   @ref Ricoh_2A03_Signal_FETCH is asserted.
--! - The @ref timing_generator and the @ref decoder_rom turn the opcode and
--!   the current cycle into the 130 @ref Ricoh_2A03_Decoder_Lines
--!   "decoder lines".
--! - The @ref random_logic_controller turns those into the control commands
--!   for the ALU and datapath, and tells the timing generator when each
--!   instruction ends. The @ref ready_controller and
--!   @ref interrupt_controller handle the `RDY`, `/IRQ`, `/NMI` and `/RES`
--!   pins.
--! - The ALU sits on SB, DB and ADL. It isn't part of the datapath, so it
--!   drives SB and ADL through the datapath's `drive_SB` and `drive_ADL`
--!   ports. Nothing outside the datapath drives DB or ADH.
--!
--! The real chip makes Phi1 and Phi2 from the Phi0 pin, with its own clock
--! generator, and outputs them to the rest of the system. Here they come from
--! outside (e.g. @ref phased_clock_generator), along with the
--! @ref metaclock that samples every latch. Each phase must last at least
--! three metaclock cycles (see @ref Ricoh_2A03_clocks).
--!
--! The real data pins are bidirectional. The FPGA fabric has no internal
--! tri-states, so they're split into `data_in` and `data_out`, and `data_out`
--! reads all ones unless the CPU is writing during Phi2.
--!
--! The data input latch and the predecode register read the pins on every
--! Phi2, writes included, and on the real chip a write puts the CPU's own value
--! on the pins. The unofficial read-modify-write opcodes (e.g. `SLO`) rely on
--! that: the latch picks up the modified value during the final write, and the
--! second operation (e.g. `ORA`) reads it from there. Since nothing guarantees
--! what `data_in` holds during a write, the CPU's latches read `data_out`
--! instead while R/W is low.
--!
--! Not implemented yet:
--!
--! - The `SO` (set overflow) pin, which drives `1/V`. `1/V` is tied low.
--! - The decimal adjust adders, so `DAA` and `DSA` have no effect, and `DSA`
--!   goes nowhere.

library ieee;
use ieee.std_logic_1164.all;

entity mos_6502 is
    port (
        --! @ref metaclock
        metaclock: in std_ulogic;
        --! @ref Ricoh_2A03_Phi1
        phi1: in std_ulogic;
        --! @ref Ricoh_2A03_Phi2
        phi2: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_RES (active-low pin)
        reset_pin_n_RES: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_IRQ (active-low pin)
        irq_pin_n_IRQ: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_NMI (active-low pin)
        nmi_pin_n_NMI: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_RDY
        ready_pin_RDY: in std_ulogic;
        --! The address pins, A0-A15. They change during Phi1, and are valid
        --! from the end of Phi1 through Phi2.
        address: out std_ulogic_vector(15 downto 0);
        --! The data pins, D0-D7, as driven by memory. They're read at the end
        --! of Phi2.
        data_in: in std_ulogic_vector(7 downto 0);
        --! The data pins, D0-D7, as driven by the CPU. All ones unless
        --! writing during Phi2.
        data_out: out std_ulogic_vector(7 downto 0);
        --! @ref Ricoh_Signal_R_NOT_W, the R/W pin. Low for the whole of a
        --! write cycle.
        read_not_write_R_NOT_W: out std_ulogic;
        --! The SYNC pin, high during an opcode fetch
        --! (@ref Ricoh_2A03_Signal_T1)
        sync_SYNC: out std_ulogic
    );
end entity;

architecture rtl of mos_6502 is
    -- #region Components
    component predecode_register is
        port(
            phi2: in std_ulogic;
            data_in: in std_ulogic_vector(7 downto 0);
            predecode_out: out std_ulogic_vector(7 downto 0);
            metaclock: in std_ulogic
        );
    end component;
    component predecode_logic is
        port(
            predecode_in: in std_ulogic_vector(7 downto 0);
            inject_brk_0_IR: in std_ulogic;
            predecode_out: out std_ulogic_vector(7 downto 0);
            short_instruction_TWOCYCLE: out std_ulogic;
            single_byte_IMPLIED: out std_ulogic
        );
    end component;
    component instruction_register is
        port(
            phi1: in std_ulogic;
            load_opcode_FETCH: in std_ulogic;
            predecode_in: in std_ulogic_vector(7 downto 0);
            instruction_out: out std_ulogic_vector(7 downto 0);
            metaclock: in std_ulogic
        );
    end component;
    component timing_generator is
        port(
            phi1: in std_ulogic;
            phi2: in std_ulogic;
            ready: in std_ulogic;
            reset_short_counter_TRES1: in std_ulogic;
            reset_counters_TRESX: in std_ulogic;
            short_instruction_TWOCYCLE: in std_ulogic;
            shift_instruction_SHIFT: in std_ulogic;
            memory_operation_MemOP: in std_ulogic;
            cycle_T0: out std_ulogic;
            cycle_T1: out std_ulogic;
            cycle_T1X: out std_ulogic;
            cycle_T2: out std_ulogic;
            cycle_T3: out std_ulogic;
            cycle_T4: out std_ulogic;
            cycle_T5: out std_ulogic;
            rmw_cycle_T6: out std_ulogic;
            rmw_cycle_T7: out std_ulogic;
            metaclock: in std_ulogic
        );
    end component;
    component decoder_rom is
        port(
            instruction_in: in std_ulogic_vector(7 downto 0);
            cycle_T0: in std_ulogic;
            cycle_T1X: in std_ulogic;
            cycle_T2: in std_ulogic;
            cycle_T3: in std_ulogic;
            cycle_T4: in std_ulogic;
            cycle_T5: in std_ulogic;
            previous_ready_PRDY: in std_ulogic;
            decoder_out: out std_ulogic_vector(129 downto 0)
        );
    end component;
    component ready_controller is
        port(
            phi1: in std_ulogic;
            phi2: in std_ulogic;
            ready_pin_RDY: in std_ulogic;
            store_cycle_STOR: in std_ulogic;
            pc_to_db_PC_DB: in std_ulogic;
            brk_t4_X98: in std_ulogic;
            push_t2_X100: in std_ulogic;
            rmw_cycle_T6: in std_ulogic;
            rmw_cycle_T7: in std_ulogic;
            resetting_DORES: in std_ulogic;
            ready: out std_ulogic;
            write_cycle_WR: out std_ulogic;
            read_not_write_R_NOT_W: out std_ulogic;
            ready_phi1_ReadyPhi1: out std_ulogic;
            previous_ready_PRDY: out std_ulogic;
            metaclock: in std_ulogic
        );
    end component;
    component interrupt_controller is
        port(
            phi1: in std_ulogic;
            phi2: in std_ulogic;
            nmi_pin_n_NMI: in std_ulogic;
            irq_pin_n_IRQ: in std_ulogic;
            reset_pin_n_RES: in std_ulogic;
            ready: in std_ulogic;
            brk_t5_X22: in std_ulogic;
            branch_t2_X80: in std_ulogic;
            cycle_T0: in std_ulogic;
            interrupt_disable_I_OUT: in std_ulogic;
            reset_pending_RESP: out std_ulogic;
            resetting_DORES: out std_ulogic;
            brk_cycle_6_end_BRK6E: out std_ulogic;
            break_flag_B_OUT: out std_ulogic;
            clear_0_ADL0: out std_ulogic;
            clear_0_ADL1: out std_ulogic;
            clear_0_ADL2: out std_ulogic;
            metaclock: in std_ulogic
        );
    end component;
    component random_logic_controller is
        port(
            phi1: in std_ulogic;
            phi2: in std_ulogic;
            decoder_in: in std_ulogic_vector(129 downto 0);
            ready: in std_ulogic;
            ready_phi1_ReadyPhi1: in std_ulogic;
            cycle_T0: in std_ulogic;
            cycle_T1: in std_ulogic;
            rmw_cycle_T6: in std_ulogic;
            rmw_cycle_T7: in std_ulogic;
            single_byte_IMPLIED: in std_ulogic;
            instruction_IR5: in std_ulogic;
            reset_pending_RESP: in std_ulogic;
            brk_cycle_6_end_BRK6E: in std_ulogic;
            break_flag_B_OUT: in std_ulogic;
            vector_0_ADL0: in std_ulogic;
            alu_carry_ACR: in std_ulogic;
            carry_flag_C_OUT: in std_ulogic;
            decimal_flag_D_OUT: in std_ulogic;
            overflow_flag_V_OUT: in std_ulogic;
            negative_flag_N_OUT: in std_ulogic;
            zero_flag_Z_OUT: in std_ulogic;
            bus_DB_in: in std_ulogic_vector(7 downto 0);
            reset_short_counter_TRES1: out std_ulogic;
            reset_counters_TRESX: out std_ulogic;
            shift_instruction_SHIFT: out std_ulogic;
            memory_operation_MemOP: out std_ulogic;
            store_cycle_STOR: out std_ulogic;
            pc_to_db_PC_DB: out std_ulogic;
            fetch_opcode_FETCH: out std_ulogic;
            inject_brk_0_IR: out std_ulogic;
            output_enable_X_SB: out std_ulogic;
            output_enable_Y_SB: out std_ulogic;
            load_SB_X: out std_ulogic;
            load_SB_Y: out std_ulogic;
            output_enable_S_SB: out std_ulogic;
            output_enable_S_ADL: out std_ulogic;
            load_SB_S: out std_ulogic;
            refresh_S_S: out std_ulogic;
            load_NDB_ADD: out std_ulogic;
            load_DB_ADD: out std_ulogic;
            load_ADL_ADD: out std_ulogic;
            load_SB_ADD: out std_ulogic;
            load_0_ADD: out std_ulogic;
            enable_ands_ANDS: out std_ulogic;
            enable_eors_EORS: out std_ulogic;
            enable_ors_ORS: out std_ulogic;
            enable_srs_SRS: out std_ulogic;
            enable_sums_SUMS: out std_ulogic;
            carry_in_I_ADDC: out std_ulogic;
            decimal_add_DAA: out std_ulogic;
            decimal_subtract_DSA: out std_ulogic;
            output_enable_ADD_SB_0_6: out std_ulogic;
            output_enable_ADD_SB_7: out std_ulogic;
            output_enable_ADD_ADL: out std_ulogic;
            load_SB_AC: out std_ulogic;
            output_enable_AC_SB: out std_ulogic;
            output_enable_AC_DB: out std_ulogic;
            increment_pc_I_PC: out std_ulogic;
            load_PCL_PCL: out std_ulogic;
            load_ADL_PCL: out std_ulogic;
            output_enable_PCL_ADL: out std_ulogic;
            output_enable_PCL_DB: out std_ulogic;
            load_PCH_PCH: out std_ulogic;
            load_ADH_PCH: out std_ulogic;
            output_enable_PCH_ADH: out std_ulogic;
            output_enable_PCH_DB: out std_ulogic;
            load_ADH_ABH: out std_ulogic;
            load_ADL_ABL: out std_ulogic;
            connect_SB_DB: out std_ulogic;
            connect_SB_ADH: out std_ulogic;
            clear_0_ADH0: out std_ulogic;
            clear_0_ADH_1_7: out std_ulogic;
            output_enable_DL_DB: out std_ulogic;
            output_enable_DL_ADL: out std_ulogic;
            output_enable_DL_ADH: out std_ulogic;
            output_enable_P_DB: out std_ulogic;
            load_DB0_C: out std_ulogic;
            load_IR5_C: out std_ulogic;
            load_ACR_C: out std_ulogic;
            load_DB1_Z: out std_ulogic;
            load_DBZ_Z: out std_ulogic;
            load_DB2_I: out std_ulogic;
            load_IR5_I: out std_ulogic;
            load_DB3_D: out std_ulogic;
            load_IR5_D: out std_ulogic;
            load_DB6_V: out std_ulogic;
            load_AVR_V: out std_ulogic;
            clear_0_V: out std_ulogic;
            load_DB7_N: out std_ulogic;
            metaclock: in std_ulogic
        );
    end component;
    component logic_core is
        port(
            adl_bus_in: in std_ulogic_vector(7 downto 0);
            adl_bus_out: out std_ulogic_vector(7 downto 0);
            sb_bus_in: in std_ulogic_vector(7 downto 0);
            sb_bus_out: out std_ulogic_vector(7 downto 0);
            db_bus_in: in std_ulogic_vector(7 downto 0);
            control_not_db_add: in std_ulogic;
            control_db_add: in std_ulogic;
            control_adl_add: in std_ulogic;
            control_sb_add: in std_ulogic;
            control_0_add: in std_ulogic;
            control_daa: in std_ulogic;
            control_i_addc: in std_ulogic;
            control_sums: in std_ulogic;
            control_ands: in std_ulogic;
            control_ors: in std_ulogic;
            control_eors: in std_ulogic;
            control_srs: in std_ulogic;
            signal_avr: out std_ulogic;
            signal_carry: out std_ulogic;
            signal_hc: out std_ulogic;
            control_add_sb_0_6: in std_ulogic;
            control_add_sb_7: in std_ulogic;
            control_add_adl: in std_ulogic;
            metaclock: in std_ulogic;
            phi2: in std_ulogic
        );
    end component;
    component mos_6502_datapath is
        port(
            data_in: in std_ulogic_vector(7 downto 0);
            data_out: out std_ulogic_vector(7 downto 0);
            address: out std_ulogic_vector(15 downto 0);
            phi1: in std_ulogic;
            phi2: in std_ulogic;
            metaclock: in std_ulogic;
            drive_SB: in std_ulogic_vector(7 downto 0);
            drive_DB: in std_ulogic_vector(7 downto 0);
            drive_ADH: in std_ulogic_vector(7 downto 0);
            drive_ADL: in std_ulogic_vector(7 downto 0);
            databus_SB: out std_ulogic_vector(7 downto 0);
            databus_DB: out std_ulogic_vector(7 downto 0);
            databus_ADH: out std_ulogic_vector(7 downto 0);
            databus_ADL: out std_ulogic_vector(7 downto 0);
            connect_SB_DB: in std_ulogic;
            connect_SB_ADH: in std_ulogic;
            clear_0_ADL0: in std_ulogic;
            clear_0_ADL1: in std_ulogic;
            clear_0_ADL2: in std_ulogic;
            clear_0_ADH0: in std_ulogic;
            clear_0_ADH_1_7: in std_ulogic;
            load_SB_AC: in std_ulogic;
            output_enable_AC_SB: in std_ulogic;
            output_enable_AC_DB: in std_ulogic;
            load_SB_X: in std_ulogic;
            output_enable_X_SB: in std_ulogic;
            load_SB_Y: in std_ulogic;
            output_enable_Y_SB: in std_ulogic;
            load_SB_S: in std_ulogic;
            output_enable_S_SB: in std_ulogic;
            output_enable_S_ADL: in std_ulogic;
            load_ADH_ABH: in std_ulogic;
            load_ADL_ABL: in std_ulogic;
            load_PCL_PCL: in std_ulogic;
            load_ADL_PCL: in std_ulogic;
            signal_I_PC: in std_ulogic;
            output_enable_PCL_DB: in std_ulogic;
            output_enable_PCL_ADL: in std_ulogic;
            load_PCH_PCH: in std_ulogic;
            load_ADH_PCH: in std_ulogic;
            output_enable_PCH_DB: in std_ulogic;
            output_enable_PCH_ADH: in std_ulogic;
            output_enable_DL_DB: in std_ulogic;
            output_enable_DL_ADL: in std_ulogic;
            output_enable_DL_ADH: in std_ulogic;
            signal_R_NOT_W: in std_ulogic;
            output_enable_P_DB: in std_ulogic;
            signal_IR5: in std_ulogic;
            signal_ACR: in std_ulogic;
            signal_AVR: in std_ulogic;
            signal_DB0_C: in std_ulogic;
            signal_IR5_C: in std_ulogic;
            signal_ACR_C: in std_ulogic;
            signal_DB1_Z: in std_ulogic;
            signal_DBZ_Z: in std_ulogic;
            signal_DB2_I: in std_ulogic;
            signal_IR5_I: in std_ulogic;
            signal_DB3_D: in std_ulogic;
            signal_IR5_D: in std_ulogic;
            signal_DB6_V: in std_ulogic;
            signal_AVR_V: in std_ulogic;
            signal_1_V: in std_ulogic;
            signal_0_V: in std_ulogic;
            signal_DB7_N: in std_ulogic;
            signal_BRK6E: in std_ulogic;
            signal_B_OUT: in std_ulogic;
            carry_flag_C_OUT: out std_ulogic;
            zero_flag_Z_OUT: out std_ulogic;
            interrupt_disable_I_OUT: out std_ulogic;
            decimal_flag_D_OUT: out std_ulogic;
            overflow_flag_V_OUT: out std_ulogic;
            negative_flag_N_OUT: out std_ulogic
        );
    end component;
    -- #endregion

    for PD: predecode_register use entity work.predecode_register;
    for PDL: predecode_logic use entity work.predecode_logic;
    for IR: instruction_register use entity work.instruction_register;
    for TG: timing_generator use entity work.timing_generator;
    for ROM: decoder_rom use entity work.decoder_rom;
    for RDY: ready_controller use entity work.ready_controller;
    for INTC: interrupt_controller use entity work.interrupt_controller;
    for RLC: random_logic_controller use entity work.random_logic_controller;
    for ALU: logic_core use entity work.logic_core;
    for DP: mos_6502_datapath use entity work.mos_6502_datapath;

    -- #region Predecode and instruction register
    signal predecode_value: std_ulogic_vector(7 downto 0);
    --! The opcode after BRK injection, on its way to the instruction register
    signal predecode_opcode: std_ulogic_vector(7 downto 0);
    signal TWOCYCLE: std_ulogic;
    signal IMPLIED: std_ulogic;
    signal instruction: std_ulogic_vector(7 downto 0);
    -- #endregion

    -- #region Timing
    signal T0: std_ulogic;
    signal T1: std_ulogic;
    signal T1X: std_ulogic;
    signal T2: std_ulogic;
    signal T3: std_ulogic;
    signal T4: std_ulogic;
    signal T5: std_ulogic;
    signal T6: std_ulogic;
    signal T7: std_ulogic;
    signal decoder_lines: std_ulogic_vector(129 downto 0);
    -- #endregion

    -- #region Ready and interrupt control
    signal ready: std_ulogic;
    signal ReadyPhi1: std_ulogic;
    signal PRDY: std_ulogic;
    signal R_NOT_W: std_ulogic;
    signal RESP: std_ulogic;
    signal DORES: std_ulogic;
    signal BRK6E: std_ulogic;
    signal B_OUT: std_ulogic;
    signal clear_0_ADL0: std_ulogic;
    signal clear_0_ADL1: std_ulogic;
    signal clear_0_ADL2: std_ulogic;
    -- #endregion

    -- #region Dispatch
    signal TRES1: std_ulogic;
    signal TRESX: std_ulogic;
    signal SHIFT: std_ulogic;
    signal MemOP: std_ulogic;
    signal STOR: std_ulogic;
    signal PC_DB: std_ulogic;
    signal FETCH: std_ulogic;
    signal inject_brk_0_IR: std_ulogic;
    -- #endregion

    -- #region Register control
    signal output_enable_X_SB: std_ulogic;
    signal output_enable_Y_SB: std_ulogic;
    signal load_SB_X: std_ulogic;
    signal load_SB_Y: std_ulogic;
    signal output_enable_S_SB: std_ulogic;
    signal output_enable_S_ADL: std_ulogic;
    signal load_SB_S: std_ulogic;
    -- #endregion

    -- #region ALU control
    signal load_NDB_ADD: std_ulogic;
    signal load_DB_ADD: std_ulogic;
    signal load_ADL_ADD: std_ulogic;
    signal load_SB_ADD: std_ulogic;
    signal load_0_ADD: std_ulogic;
    signal enable_ANDS: std_ulogic;
    signal enable_EORS: std_ulogic;
    signal enable_ORS: std_ulogic;
    signal enable_SRS: std_ulogic;
    signal enable_SUMS: std_ulogic;
    signal carry_in_I_ADDC: std_ulogic;
    signal decimal_add_DAA: std_ulogic;
    signal output_enable_ADD_SB_0_6: std_ulogic;
    signal output_enable_ADD_SB_7: std_ulogic;
    signal output_enable_ADD_ADL: std_ulogic;
    --! @ref Ricoh2A03_ALU_ACR, latched during Phi2
    signal ACR: std_ulogic;
    --! @ref Ricoh2A03_ALU_AVR, latched during Phi2
    signal AVR: std_ulogic;
    -- #endregion

    -- #region Accumulator control
    signal load_SB_AC: std_ulogic;
    signal output_enable_AC_SB: std_ulogic;
    signal output_enable_AC_DB: std_ulogic;
    -- #endregion

    -- #region Program counter control
    signal increment_pc_I_PC: std_ulogic;
    signal load_PCL_PCL: std_ulogic;
    signal load_ADL_PCL: std_ulogic;
    signal output_enable_PCL_ADL: std_ulogic;
    signal output_enable_PCL_DB: std_ulogic;
    signal load_PCH_PCH: std_ulogic;
    signal load_ADH_PCH: std_ulogic;
    signal output_enable_PCH_ADH: std_ulogic;
    signal output_enable_PCH_DB: std_ulogic;
    -- #endregion

    -- #region Bus control
    signal load_ADH_ABH: std_ulogic;
    signal load_ADL_ABL: std_ulogic;
    signal connect_SB_DB: std_ulogic;
    signal connect_SB_ADH: std_ulogic;
    signal clear_0_ADH0: std_ulogic;
    signal clear_0_ADH_1_7: std_ulogic;
    signal output_enable_DL_DB: std_ulogic;
    signal output_enable_DL_ADL: std_ulogic;
    signal output_enable_DL_ADH: std_ulogic;
    -- #endregion

    -- #region Flags control
    signal output_enable_P_DB: std_ulogic;
    signal load_DB0_C: std_ulogic;
    signal load_IR5_C: std_ulogic;
    signal load_ACR_C: std_ulogic;
    signal load_DB1_Z: std_ulogic;
    signal load_DBZ_Z: std_ulogic;
    signal load_DB2_I: std_ulogic;
    signal load_IR5_I: std_ulogic;
    signal load_DB3_D: std_ulogic;
    signal load_IR5_D: std_ulogic;
    signal load_DB6_V: std_ulogic;
    signal load_AVR_V: std_ulogic;
    signal clear_0_V: std_ulogic;
    signal load_DB7_N: std_ulogic;
    signal C_OUT: std_ulogic;
    signal Z_OUT: std_ulogic;
    signal I_OUT: std_ulogic;
    signal D_OUT: std_ulogic;
    signal V_OUT: std_ulogic;
    signal N_OUT: std_ulogic;
    -- #endregion

    -- #region Buses
    --! What the CPU drives onto the data pins: `data_out`, read back into
    --! the CPU while writing
    signal cpu_data_out: std_ulogic_vector(7 downto 0);
    --! The value on the data pins: `cpu_data_out` during a write, otherwise
    --! `data_in` from memory
    signal data_pins: std_ulogic_vector(7 downto 0);
    --! @ref Ricoh_2A03_SB, as resolved by the datapath
    signal bus_SB: std_ulogic_vector(7 downto 0);
    --! @ref Ricoh_2A03_DB, as resolved by the datapath
    signal bus_DB: std_ulogic_vector(7 downto 0);
    --! @ref Ricoh_2A03_ADL, as resolved by the datapath
    signal bus_ADL: std_ulogic_vector(7 downto 0);
    --! The adder hold register driving SB (`ADD/SB`), all ones when it isn't
    signal alu_drive_SB: std_ulogic_vector(7 downto 0);
    --! The adder hold register driving ADL (`ADD/ADL`), all ones when it isn't
    signal alu_drive_ADL: std_ulogic_vector(7 downto 0);
    -- #endregion
begin
    -- #region Instruction decoder
    PD: predecode_register
        port map(
            phi2 => phi2,
            data_in => data_pins,
            predecode_out => predecode_value,
            metaclock => metaclock
        );
    PDL: predecode_logic
        port map(
            predecode_in => predecode_value,
            inject_brk_0_IR => inject_brk_0_IR,
            predecode_out => predecode_opcode,
            short_instruction_TWOCYCLE => TWOCYCLE,
            single_byte_IMPLIED => IMPLIED
        );
    IR: instruction_register
        port map(
            phi1 => phi1,
            load_opcode_FETCH => FETCH,
            predecode_in => predecode_opcode,
            instruction_out => instruction,
            metaclock => metaclock
        );
    TG: timing_generator
        port map(
            phi1 => phi1,
            phi2 => phi2,
            ready => ready,
            reset_short_counter_TRES1 => TRES1,
            reset_counters_TRESX => TRESX,
            short_instruction_TWOCYCLE => TWOCYCLE,
            shift_instruction_SHIFT => SHIFT,
            memory_operation_MemOP => MemOP,
            cycle_T0 => T0,
            cycle_T1 => T1,
            cycle_T1X => T1X,
            cycle_T2 => T2,
            cycle_T3 => T3,
            cycle_T4 => T4,
            cycle_T5 => T5,
            rmw_cycle_T6 => T6,
            rmw_cycle_T7 => T7,
            metaclock => metaclock
        );
    ROM: decoder_rom
        port map(
            instruction_in => instruction,
            cycle_T0 => T0,
            cycle_T1X => T1X,
            cycle_T2 => T2,
            cycle_T3 => T3,
            cycle_T4 => T4,
            cycle_T5 => T5,
            previous_ready_PRDY => PRDY,
            decoder_out => decoder_lines
        );
    RDY: ready_controller
        port map(
            phi1 => phi1,
            phi2 => phi2,
            ready_pin_RDY => ready_pin_RDY,
            store_cycle_STOR => STOR,
            pc_to_db_PC_DB => PC_DB,
            brk_t4_X98 => decoder_lines(98),
            push_t2_X100 => decoder_lines(100),
            rmw_cycle_T6 => T6,
            rmw_cycle_T7 => T7,
            resetting_DORES => DORES,
            ready => ready,
            write_cycle_WR => open,
            read_not_write_R_NOT_W => R_NOT_W,
            ready_phi1_ReadyPhi1 => ReadyPhi1,
            previous_ready_PRDY => PRDY,
            metaclock => metaclock
        );
    INTC: interrupt_controller
        port map(
            phi1 => phi1,
            phi2 => phi2,
            nmi_pin_n_NMI => nmi_pin_n_NMI,
            irq_pin_n_IRQ => irq_pin_n_IRQ,
            reset_pin_n_RES => reset_pin_n_RES,
            ready => ready,
            brk_t5_X22 => decoder_lines(22),
            branch_t2_X80 => decoder_lines(80),
            cycle_T0 => T0,
            interrupt_disable_I_OUT => I_OUT,
            reset_pending_RESP => RESP,
            resetting_DORES => DORES,
            brk_cycle_6_end_BRK6E => BRK6E,
            break_flag_B_OUT => B_OUT,
            clear_0_ADL0 => clear_0_ADL0,
            clear_0_ADL1 => clear_0_ADL1,
            clear_0_ADL2 => clear_0_ADL2,
            metaclock => metaclock
        );
    RLC: random_logic_controller
        port map(
            phi1 => phi1,
            phi2 => phi2,
            decoder_in => decoder_lines,
            ready => ready,
            ready_phi1_ReadyPhi1 => ReadyPhi1,
            cycle_T0 => T0,
            cycle_T1 => T1,
            rmw_cycle_T6 => T6,
            rmw_cycle_T7 => T7,
            single_byte_IMPLIED => IMPLIED,
            instruction_IR5 => instruction(5),
            reset_pending_RESP => RESP,
            brk_cycle_6_end_BRK6E => BRK6E,
            break_flag_B_OUT => B_OUT,
            vector_0_ADL0 => clear_0_ADL0,
            alu_carry_ACR => ACR,
            carry_flag_C_OUT => C_OUT,
            decimal_flag_D_OUT => D_OUT,
            overflow_flag_V_OUT => V_OUT,
            negative_flag_N_OUT => N_OUT,
            zero_flag_Z_OUT => Z_OUT,
            bus_DB_in => bus_DB,
            reset_short_counter_TRES1 => TRES1,
            reset_counters_TRESX => TRESX,
            shift_instruction_SHIFT => SHIFT,
            memory_operation_MemOP => MemOP,
            store_cycle_STOR => STOR,
            pc_to_db_PC_DB => PC_DB,
            fetch_opcode_FETCH => FETCH,
            inject_brk_0_IR => inject_brk_0_IR,
            output_enable_X_SB => output_enable_X_SB,
            output_enable_Y_SB => output_enable_Y_SB,
            load_SB_X => load_SB_X,
            load_SB_Y => load_SB_Y,
            output_enable_S_SB => output_enable_S_SB,
            output_enable_S_ADL => output_enable_S_ADL,
            load_SB_S => load_SB_S,
            -- The stack pointer holds its value without a refresh
            refresh_S_S => open,
            load_NDB_ADD => load_NDB_ADD,
            load_DB_ADD => load_DB_ADD,
            load_ADL_ADD => load_ADL_ADD,
            load_SB_ADD => load_SB_ADD,
            load_0_ADD => load_0_ADD,
            enable_ands_ANDS => enable_ANDS,
            enable_eors_EORS => enable_EORS,
            enable_ors_ORS => enable_ORS,
            enable_srs_SRS => enable_SRS,
            enable_sums_SUMS => enable_SUMS,
            carry_in_I_ADDC => carry_in_I_ADDC,
            decimal_add_DAA => decimal_add_DAA,
            -- The decimal adjust adders aren't implemented yet
            decimal_subtract_DSA => open,
            output_enable_ADD_SB_0_6 => output_enable_ADD_SB_0_6,
            output_enable_ADD_SB_7 => output_enable_ADD_SB_7,
            output_enable_ADD_ADL => output_enable_ADD_ADL,
            load_SB_AC => load_SB_AC,
            output_enable_AC_SB => output_enable_AC_SB,
            output_enable_AC_DB => output_enable_AC_DB,
            increment_pc_I_PC => increment_pc_I_PC,
            load_PCL_PCL => load_PCL_PCL,
            load_ADL_PCL => load_ADL_PCL,
            output_enable_PCL_ADL => output_enable_PCL_ADL,
            output_enable_PCL_DB => output_enable_PCL_DB,
            load_PCH_PCH => load_PCH_PCH,
            load_ADH_PCH => load_ADH_PCH,
            output_enable_PCH_ADH => output_enable_PCH_ADH,
            output_enable_PCH_DB => output_enable_PCH_DB,
            load_ADH_ABH => load_ADH_ABH,
            load_ADL_ABL => load_ADL_ABL,
            connect_SB_DB => connect_SB_DB,
            connect_SB_ADH => connect_SB_ADH,
            clear_0_ADH0 => clear_0_ADH0,
            clear_0_ADH_1_7 => clear_0_ADH_1_7,
            output_enable_DL_DB => output_enable_DL_DB,
            output_enable_DL_ADL => output_enable_DL_ADL,
            output_enable_DL_ADH => output_enable_DL_ADH,
            output_enable_P_DB => output_enable_P_DB,
            load_DB0_C => load_DB0_C,
            load_IR5_C => load_IR5_C,
            load_ACR_C => load_ACR_C,
            load_DB1_Z => load_DB1_Z,
            load_DBZ_Z => load_DBZ_Z,
            load_DB2_I => load_DB2_I,
            load_IR5_I => load_IR5_I,
            load_DB3_D => load_DB3_D,
            load_IR5_D => load_IR5_D,
            load_DB6_V => load_DB6_V,
            load_AVR_V => load_AVR_V,
            clear_0_V => clear_0_V,
            load_DB7_N => load_DB7_N,
            metaclock => metaclock
        );
    -- #endregion

    ALU: logic_core
        port map(
            adl_bus_in => bus_ADL,
            adl_bus_out => alu_drive_ADL,
            sb_bus_in => bus_SB,
            sb_bus_out => alu_drive_SB,
            db_bus_in => bus_DB,
            control_not_db_add => load_NDB_ADD,
            control_db_add => load_DB_ADD,
            control_adl_add => load_ADL_ADD,
            control_sb_add => load_SB_ADD,
            control_0_add => load_0_ADD,
            control_daa => decimal_add_DAA,
            control_i_addc => carry_in_I_ADDC,
            control_sums => enable_SUMS,
            control_ands => enable_ANDS,
            control_ors => enable_ORS,
            control_eors => enable_EORS,
            control_srs => enable_SRS,
            signal_avr => AVR,
            signal_carry => ACR,
            signal_hc => open,
            control_add_sb_0_6 => output_enable_ADD_SB_0_6,
            control_add_sb_7 => output_enable_ADD_SB_7,
            control_add_adl => output_enable_ADD_ADL,
            metaclock => metaclock,
            phi2 => phi2
        );

    DP: mos_6502_datapath
        port map(
            data_in => data_pins,
            data_out => cpu_data_out,
            address => address,
            phi1 => phi1,
            phi2 => phi2,
            metaclock => metaclock,
            drive_SB => alu_drive_SB,
            -- Nothing outside the datapath drives DB or ADH, so they get all
            -- ones, which leave a precharged bus alone.
            drive_DB => (others => '1'),
            drive_ADH => (others => '1'),
            drive_ADL => alu_drive_ADL,
            databus_SB => bus_SB,
            databus_DB => bus_DB,
            databus_ADH => open,
            databus_ADL => bus_ADL,
            connect_SB_DB => connect_SB_DB,
            connect_SB_ADH => connect_SB_ADH,
            clear_0_ADL0 => clear_0_ADL0,
            clear_0_ADL1 => clear_0_ADL1,
            clear_0_ADL2 => clear_0_ADL2,
            clear_0_ADH0 => clear_0_ADH0,
            clear_0_ADH_1_7 => clear_0_ADH_1_7,
            load_SB_AC => load_SB_AC,
            output_enable_AC_SB => output_enable_AC_SB,
            output_enable_AC_DB => output_enable_AC_DB,
            load_SB_X => load_SB_X,
            output_enable_X_SB => output_enable_X_SB,
            load_SB_Y => load_SB_Y,
            output_enable_Y_SB => output_enable_Y_SB,
            load_SB_S => load_SB_S,
            output_enable_S_SB => output_enable_S_SB,
            output_enable_S_ADL => output_enable_S_ADL,
            load_ADH_ABH => load_ADH_ABH,
            load_ADL_ABL => load_ADL_ABL,
            load_PCL_PCL => load_PCL_PCL,
            load_ADL_PCL => load_ADL_PCL,
            signal_I_PC => increment_pc_I_PC,
            output_enable_PCL_DB => output_enable_PCL_DB,
            output_enable_PCL_ADL => output_enable_PCL_ADL,
            load_PCH_PCH => load_PCH_PCH,
            load_ADH_PCH => load_ADH_PCH,
            output_enable_PCH_DB => output_enable_PCH_DB,
            output_enable_PCH_ADH => output_enable_PCH_ADH,
            output_enable_DL_DB => output_enable_DL_DB,
            output_enable_DL_ADL => output_enable_DL_ADL,
            output_enable_DL_ADH => output_enable_DL_ADH,
            signal_R_NOT_W => R_NOT_W,
            output_enable_P_DB => output_enable_P_DB,
            signal_IR5 => instruction(5),
            signal_ACR => ACR,
            signal_AVR => AVR,
            signal_DB0_C => load_DB0_C,
            signal_IR5_C => load_IR5_C,
            signal_ACR_C => load_ACR_C,
            signal_DB1_Z => load_DB1_Z,
            signal_DBZ_Z => load_DBZ_Z,
            signal_DB2_I => load_DB2_I,
            signal_IR5_I => load_IR5_I,
            signal_DB3_D => load_DB3_D,
            signal_IR5_D => load_IR5_D,
            signal_DB6_V => load_DB6_V,
            signal_AVR_V => load_AVR_V,
            -- The SO pin isn't implemented yet
            signal_1_V => '0',
            signal_0_V => clear_0_V,
            signal_DB7_N => load_DB7_N,
            signal_BRK6E => BRK6E,
            signal_B_OUT => B_OUT,
            carry_flag_C_OUT => C_OUT,
            zero_flag_Z_OUT => Z_OUT,
            interrupt_disable_I_OUT => I_OUT,
            decimal_flag_D_OUT => D_OUT,
            overflow_flag_V_OUT => V_OUT,
            negative_flag_N_OUT => N_OUT
        );

    data_out <= cpu_data_out;
    data_pins <= cpu_data_out when R_NOT_W = '0' else data_in;
    read_not_write_R_NOT_W <= R_NOT_W;
    sync_SYNC <= T1;
end architecture;
