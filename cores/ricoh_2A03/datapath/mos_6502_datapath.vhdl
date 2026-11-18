--! @file mos_6502_datapath.vhdl
--! @brief Wrapper component holding the data input/output latches, the
--! accumulator and index registers, the address registers, the program
--! counter, the stack pointer, the status register, and the bus multiplexer.
--! @details The internal buses (SB, DB, ADH, ADL) are driven by several
--! subunits at once, each driving all ones (the precharge level) when it isn't
--! enabled. Each subunit drives its own signal for each bus (e.g. `AC_DB`),
--! and every bus's drivers, including the ones from outside the datapath
--! (drive_*), are ANDed together, the same wired-AND as the real chip's
--! precharged buses. The @ref bus_multiplexer then applies the open drain
--! MOSFETs and the pass MOSFETs to give the bus values (bus_*) that every
--! subunit reads.

library ieee;
use ieee.std_logic_1164.all;

entity mos_6502_datapath is
    port(
        --! The external-facing data pins, as read by the data input latch.
        --! The real pins are bidirectional, but the FPGA fabric has no internal
        --! tri-states, so they're split into `data_in` and `data_out`.
        data_in: in std_ulogic_vector(7 downto 0);
        --! The external-facing data pins, as driven by the data output
        --! register. All ones unless writing (`R/W` low) during Phi2; the real
        --! pins would be released.
        data_out: out std_ulogic_vector(7 downto 0);
        --! The external-facing address pins
        address: out std_ulogic_vector(15 downto 0);
        --! @ref Ricoh_2A03_Phi1
        phi1: in std_ulogic;
        --! @ref Ricoh_2A03_Phi2
        phi2: in std_ulogic;
        --! @ref metaclock
        metaclock: in std_ulogic;

        -- #region Buses
        --! Drives @ref Ricoh_2A03_SB from outside the datapath (e.g. the
        --! ALU's adder hold register), all ones when not driving
        drive_SB: in std_ulogic_vector(7 downto 0);
        --! Drives @ref Ricoh_2A03_DB from outside the datapath, all ones when
        --! not driving
        drive_DB: in std_ulogic_vector(7 downto 0);
        --! Drives @ref Ricoh_2A03_ADH from outside the datapath, all ones
        --! when not driving
        drive_ADH: in std_ulogic_vector(7 downto 0);
        --! Drives @ref Ricoh_2A03_ADL from outside the datapath (e.g. the
        --! ALU's adder hold register), all ones when not driving
        drive_ADL: in std_ulogic_vector(7 downto 0);
        --! @ref Ricoh_2A03_SB, as resolved by @ref bus_multiplexer
        databus_SB: out std_ulogic_vector(7 downto 0);
        --! @ref Ricoh_2A03_DB, as resolved by @ref bus_multiplexer
        databus_DB: out std_ulogic_vector(7 downto 0);
        --! @ref Ricoh_2A03_ADH, as resolved by @ref bus_multiplexer
        databus_ADH: out std_ulogic_vector(7 downto 0);
        --! @ref Ricoh_2A03_ADL, as resolved by @ref bus_multiplexer
        databus_ADL: out std_ulogic_vector(7 downto 0);
        -- #endregion

        -- #region Control signals

        -- Bus multiplexer
        --! @ref Ricoh_2A03_Signal_SB_DB
        connect_SB_DB: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_SB_ADH
        connect_SB_ADH: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_0_ADL0
        clear_0_ADL0: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_0_ADL1
        clear_0_ADL1: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_0_ADL2
        clear_0_ADL2: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_0_ADH0
        clear_0_ADH0: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_0_ADH_1_7
        clear_0_ADH_1_7: in std_ulogic;

        -- Accumulator
        --! @ref Ricoh_Signal_SB_AC
        load_SB_AC: in std_ulogic;
        --! @ref Ricoh_Signal_AC_SB
        output_enable_AC_SB: in std_ulogic;
        --! @ref Ricoh_Signal_AC_DB
        output_enable_AC_DB: in std_ulogic;

        -- Index registers
        --! @ref Ricoh_Signal_SB_X
        load_SB_X: in std_ulogic;
        --! @ref Ricoh_Signal_X_SB
        output_enable_X_SB: in std_ulogic;
        --! @ref Ricoh_Signal_SB_Y
        load_SB_Y: in std_ulogic;
        --! @ref Ricoh_Signal_Y_SB
        output_enable_Y_SB: in std_ulogic;

        -- Stack pointer
        --! @ref Ricoh_2A03_Signal_SB_S
        load_SB_S: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_S_SB
        output_enable_S_SB: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_S_ADL
        output_enable_S_ADL: in std_ulogic;

        -- Address bus registers
        --! @ref Ricoh_2A03_Signal_ADH_ABH
        load_ADH_ABH: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_ADL_ABL
        load_ADL_ABL: in std_ulogic;

        -- Program counter
        --! @ref Ricoh_2A03_Signal_PCL_PCL
        load_PCL_PCL: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_ADL_PCL
        load_ADL_PCL: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_I_PC
        signal_I_PC: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_PCL_DB
        output_enable_PCL_DB: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_PCL_ADL
        output_enable_PCL_ADL: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_PCH_PCH
        load_PCH_PCH: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_ADH_PCH
        load_ADH_PCH: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_PCH_DB
        output_enable_PCH_DB: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_PCH_ADH
        output_enable_PCH_ADH: in std_ulogic;

        -- Data latches
        --! @ref Ricoh_2A03_Signal_DL_DB
        output_enable_DL_DB: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_DL_ADL
        output_enable_DL_ADL: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_DL_ADH
        output_enable_DL_ADH: in std_ulogic;
        --! @ref Ricoh_Signal_R_NOT_W
        signal_R_NOT_W: in std_ulogic;

        -- Status register
        --! @ref Ricoh_Signal_P_DB
        output_enable_P_DB: in std_ulogic;
        --! Bit 5 of the instruction register
        signal_IR5: in std_ulogic;
        --! @ref Ricoh2A03_ALU_ACR
        signal_ACR: in std_ulogic;
        --! @ref Ricoh2A03_ALU_AVR
        signal_AVR: in std_ulogic;
        --! @ref Ricoh_Signal_DB0_C
        signal_DB0_C: in std_ulogic;
        --! @ref Ricoh_Signal_IR5_C
        signal_IR5_C: in std_ulogic;
        --! @ref Ricoh_Signal_ACR_C
        signal_ACR_C: in std_ulogic;
        --! @ref Ricoh_Signal_DB1_Z
        signal_DB1_Z: in std_ulogic;
        --! @ref Ricoh_Signal_DBZ_Z
        signal_DBZ_Z: in std_ulogic;
        --! @ref Ricoh_Signal_DB2_I
        signal_DB2_I: in std_ulogic;
        --! @ref Ricoh_Signal_IR5_I
        signal_IR5_I: in std_ulogic;
        --! @ref Ricoh_Signal_DB3_D
        signal_DB3_D: in std_ulogic;
        --! @ref Ricoh_Signal_IR5_D
        signal_IR5_D: in std_ulogic;
        --! @ref Ricoh_Signal_DB6_V
        signal_DB6_V: in std_ulogic;
        --! @ref Ricoh_Signal_AVR_V
        signal_AVR_V: in std_ulogic;
        --! @ref Ricoh_Signal_1_V
        signal_1_V: in std_ulogic;
        --! @ref Ricoh_Signal_0_V
        signal_0_V: in std_ulogic;
        --! @ref Ricoh_Signal_DB7_N
        signal_DB7_N: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_BRK6E, which sets I
        signal_BRK6E: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_B_OUT, pushed as bit 4 of P
        signal_B_OUT: in std_ulogic;
        -- #endregion

        -- #region Flags
        --! @ref Ricoh_2A03_Signal_C_OUT
        carry_flag_C_OUT: out std_ulogic;
        --! @ref Ricoh_2A03_Signal_Z_OUT
        zero_flag_Z_OUT: out std_ulogic;
        --! @ref Ricoh_2A03_Signal_I_OUT
        interrupt_disable_I_OUT: out std_ulogic;
        --! @ref Ricoh_2A03_Signal_D_OUT
        decimal_flag_D_OUT: out std_ulogic;
        --! @ref Ricoh_2A03_Signal_V_OUT
        overflow_flag_V_OUT: out std_ulogic;
        --! @ref Ricoh_2A03_Signal_N_OUT
        negative_flag_N_OUT: out std_ulogic
        -- #endregion
    );
end entity;

architecture rtl of mos_6502_datapath is
    -- #region Components
    component bus_multiplexer is
        port(
            drive_SB: in std_ulogic_vector(7 downto 0);
            drive_DB: in std_ulogic_vector(7 downto 0);
            drive_ADH: in std_ulogic_vector(7 downto 0);
            drive_ADL: in std_ulogic_vector(7 downto 0);
            connect_SB_DB: in std_ulogic;
            connect_SB_ADH: in std_ulogic;
            clear_0_ADL0: in std_ulogic;
            clear_0_ADL1: in std_ulogic;
            clear_0_ADL2: in std_ulogic;
            clear_0_ADH0: in std_ulogic;
            clear_0_ADH_1_7: in std_ulogic;
            bus_SB: out std_ulogic_vector(7 downto 0);
            bus_DB: out std_ulogic_vector(7 downto 0);
            bus_ADH: out std_ulogic_vector(7 downto 0);
            bus_ADL: out std_ulogic_vector(7 downto 0)
        );
    end component;
    component accumulator is
        port(
            databus_SB_in: in std_ulogic_vector(7 downto 0);
            databus_SB_out: out std_ulogic_vector(7 downto 0);
            databus_DB: out std_ulogic_vector(7 downto 0);
            load_SB_AC: in std_ulogic;
            output_enable_AC_SB: in std_ulogic;
            output_enable_AC_DB: in std_ulogic;
            metaclock: in std_ulogic
        );
    end component;
    component index_register is
        port(
            data_in: in std_ulogic_vector(7 downto 0);
            load: in std_ulogic;
            data_out: out std_ulogic_vector(7 downto 0);
            output_enable: in std_ulogic;
            metaclock: in std_ulogic
        );
    end component;
    component stack_pointer is
        port(
            phi2: in std_ulogic;
            signal_S_SB: in std_ulogic;
            signal_S_ADL: in std_ulogic;
            signal_SB_S: in std_ulogic;
            bus_SB_in: in std_ulogic_vector(7 downto 0);
            bus_SB_out: out std_ulogic_vector(7 downto 0);
            bus_ADL: out std_ulogic_vector(7 downto 0);
            metaclock: in std_ulogic
        );
    end component;
    component data_input_latch is
        port(
            load: in std_ulogic;
            data_in: in std_ulogic_vector(7 downto 0);
            db_bus_enable_DL_DB: in std_ulogic;
            db_bus_port: out std_ulogic_vector(7 downto 0);
            adh_bus_enable_DL_ADH: in std_ulogic;
            adh_bus_port: out std_ulogic_vector(7 downto 0);
            adl_bus_enable_DL_ADL: in std_ulogic;
            adl_bus_port: out std_ulogic_vector(7 downto 0);
            metaclock: in std_ulogic
        );
    end component;
    component data_output_latch is
        port(
            phi1: in std_ulogic;
            phi2: in std_ulogic;
            signal_R_NOT_W: in std_ulogic;
            data_in: in std_ulogic_vector(7 downto 0);
            data_out: out std_ulogic_vector(7 downto 0);
            metaclock: in std_ulogic
        );
    end component;
    component status_register is
        port(
            phi1: in std_ulogic;
            db_bus_in: in std_ulogic_vector(7 downto 0);
            db_bus_out: out std_ulogic_vector(7 downto 0);
            enable_P_DB: in std_ulogic;
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
            brk_cycle_6_end_BRK6E: in std_ulogic;
            break_flag_B_OUT: in std_ulogic;
            carry_flag_C_OUT: out std_ulogic;
            zero_flag_Z_OUT: out std_ulogic;
            interrupt_disable_I_OUT: out std_ulogic;
            decimal_flag_D_OUT: out std_ulogic;
            overflow_flag_V_OUT: out std_ulogic;
            negative_flag_N_OUT: out std_ulogic;
            metaclock: in std_ulogic
        );
    end component;
    component program_counter_low is
        port(
            phi2: in std_ulogic;
            signal_PCL_DB: in std_ulogic;
            signal_PCL_ADL: in std_ulogic;
            signal_1_PC: in std_ulogic;
            signal_PCL_PCL: in std_ulogic;
            signal_ADL_PCL: in std_ulogic;
            signal_PCLC: out std_ulogic;
            bus_ADL_in: in std_ulogic_vector(7 downto 0);
            bus_ADL_out: out std_ulogic_vector(7 downto 0);
            bus_DB: out std_ulogic_vector(7 downto 0);
            metaclock: in std_ulogic
        );
    end component;
    component program_counter_high is
        port(
            phi2: in std_ulogic;
            signal_PCH_DB: in std_ulogic;
            signal_PCH_ADH: in std_ulogic;
            signal_PCLC: in std_ulogic;
            signal_PCH_PCH: in std_ulogic;
            signal_ADH_PCH: in std_ulogic;
            bus_ADH_in: in std_ulogic_vector(7 downto 0);
            bus_ADH_out: out std_ulogic_vector(7 downto 0);
            bus_DB: out std_ulogic_vector(7 downto 0);
            metaclock: in std_ulogic
        );
    end component;
    -- #endregion

    for MUX: bus_multiplexer use entity work.bus_multiplexer;
    for ACC: accumulator use entity work.accumulator;
    for X_REG, Y_REG, ABH_REG, ABL_REG: index_register use entity work.index_register;
    for S_REG: stack_pointer use entity work.stack_pointer;
    for P_REG: status_register use entity work.status_register;
    for DL: data_input_latch use entity work.data_input_latch;
    for DOR: data_output_latch use entity work.data_output_latch;
    for PCL: program_counter_low use entity work.program_counter_low;
    for PCH: program_counter_high use entity work.program_counter_high;

    -- #region Buses
    --! What each subunit drives onto each bus: its value while enabled, and
    --! all ones otherwise
    signal AC_SB, X_SB, Y_SB, S_SB: std_ulogic_vector(7 downto 0);
    signal AC_DB, P_DB, DL_DB, PCL_DB, PCH_DB: std_ulogic_vector(7 downto 0);
    signal DL_ADH, PCH_ADH: std_ulogic_vector(7 downto 0);
    signal S_ADL, DL_ADL, PCL_ADL: std_ulogic_vector(7 downto 0);
    --! Every driver of each bus, ANDed together (the wired-AND)
    signal drivers_SB: std_ulogic_vector(7 downto 0);
    signal drivers_DB: std_ulogic_vector(7 downto 0);
    signal drivers_ADH: std_ulogic_vector(7 downto 0);
    signal drivers_ADL: std_ulogic_vector(7 downto 0);
    --! The value of each bus, as resolved by the bus multiplexer
    signal bus_SB: std_ulogic_vector(7 downto 0);
    signal bus_DB: std_ulogic_vector(7 downto 0);
    signal bus_ADH: std_ulogic_vector(7 downto 0);
    signal bus_ADL: std_ulogic_vector(7 downto 0);
    -- #endregion

    --! The address bus registers load from ADH/ADL during phi1
    signal load_ABH: std_ulogic;
    signal load_ABL: std_ulogic;

    --! The program counter select registers only load during phi1; during
    --! phi2 the increment logic's result is latched into PCL and PCH, and the
    --! ADL and ADH buses are precharged.
    signal load_PCLS_from_PCL: std_ulogic;
    signal load_PCLS_from_ADL: std_ulogic;
    signal load_PCHS_from_PCH: std_ulogic;
    signal load_PCHS_from_ADH: std_ulogic;
    --! @ref Ricoh_2A03_PCLC
    signal signal_PCLC: std_ulogic;
begin
    -- #region Buses
    drivers_SB <= AC_SB and X_SB and Y_SB and S_SB and drive_SB;
    drivers_DB <= AC_DB and P_DB and DL_DB and PCL_DB and PCH_DB and drive_DB;
    drivers_ADH <= DL_ADH and PCH_ADH and drive_ADH;
    drivers_ADL <= S_ADL and DL_ADL and PCL_ADL and drive_ADL;

    MUX: bus_multiplexer
        port map(
            drive_SB => drivers_SB,
            drive_DB => drivers_DB,
            drive_ADH => drivers_ADH,
            drive_ADL => drivers_ADL,
            connect_SB_DB => connect_SB_DB,
            connect_SB_ADH => connect_SB_ADH,
            clear_0_ADL0 => clear_0_ADL0,
            clear_0_ADL1 => clear_0_ADL1,
            clear_0_ADL2 => clear_0_ADL2,
            clear_0_ADH0 => clear_0_ADH0,
            clear_0_ADH_1_7 => clear_0_ADH_1_7,
            bus_SB => bus_SB,
            bus_DB => bus_DB,
            bus_ADH => bus_ADH,
            bus_ADL => bus_ADL
        );

    databus_SB <= bus_SB;
    databus_DB <= bus_DB;
    databus_ADH <= bus_ADH;
    databus_ADL <= bus_ADL;
    -- #endregion

    ACC: accumulator
        port map(
            databus_SB_in => bus_SB,
            databus_SB_out => AC_SB,
            databus_DB => AC_DB,
            load_SB_AC => load_SB_AC,
            output_enable_AC_SB => output_enable_AC_SB,
            output_enable_AC_DB => output_enable_AC_DB,
            metaclock => metaclock
        );
    X_REG: index_register
        port map(
            data_in => bus_SB,
            load => load_SB_X,
            data_out => X_SB,
            output_enable => output_enable_X_SB,
            metaclock => metaclock
        );
    Y_REG: index_register
        port map(
            data_in => bus_SB,
            load => load_SB_Y,
            data_out => Y_SB,
            output_enable => output_enable_Y_SB,
            metaclock => metaclock
        );
    S_REG: stack_pointer
        port map(
            phi2 => phi2,
            signal_S_SB => output_enable_S_SB,
            signal_S_ADL => output_enable_S_ADL,
            signal_SB_S => load_SB_S,
            bus_SB_in => bus_SB,
            bus_SB_out => S_SB,
            bus_ADL => S_ADL,
            metaclock => metaclock
        );
    P_REG: status_register
        port map(
            phi1 => phi1,
            db_bus_in => bus_DB,
            db_bus_out => P_DB,
            enable_P_DB => output_enable_P_DB,
            signal_IR5 => signal_IR5,
            signal_ACR => signal_ACR,
            signal_AVR => signal_AVR,
            signal_DB0_C => signal_DB0_C,
            signal_IR5_C => signal_IR5_C,
            signal_ACR_C => signal_ACR_C,
            signal_DB1_Z => signal_DB1_Z,
            signal_DBZ_Z => signal_DBZ_Z,
            signal_DB2_I => signal_DB2_I,
            signal_IR5_I => signal_IR5_I,
            signal_DB3_D => signal_DB3_D,
            signal_IR5_D => signal_IR5_D,
            signal_DB6_V => signal_DB6_V,
            signal_AVR_V => signal_AVR_V,
            signal_1_V => signal_1_V,
            signal_0_V => signal_0_V,
            signal_DB7_N => signal_DB7_N,
            brk_cycle_6_end_BRK6E => signal_BRK6E,
            break_flag_B_OUT => signal_B_OUT,
            carry_flag_C_OUT => carry_flag_C_OUT,
            zero_flag_Z_OUT => zero_flag_Z_OUT,
            interrupt_disable_I_OUT => interrupt_disable_I_OUT,
            decimal_flag_D_OUT => decimal_flag_D_OUT,
            overflow_flag_V_OUT => overflow_flag_V_OUT,
            negative_flag_N_OUT => negative_flag_N_OUT,
            metaclock => metaclock
        );
    load_ABH <= load_ADH_ABH and phi1;
    ABH_REG: index_register
        port map(
            data_in => bus_ADH,
            load => load_ABH,
            data_out => address(15 downto 8),
            output_enable => '1',
            metaclock => metaclock
        );
    load_ABL <= load_ADL_ABL and phi1;
    ABL_REG: index_register
        port map(
            data_in => bus_ADL,
            load => load_ABL,
            data_out => address(7 downto 0),
            output_enable => '1',
            metaclock => metaclock
        );
    DL: data_input_latch
        port map(
            load => phi2,
            data_in => data_in,
            db_bus_enable_DL_DB => output_enable_DL_DB,
            db_bus_port => DL_DB,
            adh_bus_enable_DL_ADH => output_enable_DL_ADH,
            adh_bus_port => DL_ADH,
            adl_bus_enable_DL_ADL => output_enable_DL_ADL,
            adl_bus_port => DL_ADL,
            metaclock => metaclock
        );
    DOR: data_output_latch
        port map(
            phi1 => phi1,
            phi2 => phi2,
            signal_R_NOT_W => signal_R_NOT_W,
            data_in => bus_DB,
            data_out => data_out,
            metaclock => metaclock
        );

    load_PCLS_from_PCL <= load_PCL_PCL and phi1;
    load_PCLS_from_ADL <= load_ADL_PCL and phi1;
    PCL: program_counter_low
        port map(
            phi2 => phi2,
            signal_PCL_DB => output_enable_PCL_DB,
            signal_PCL_ADL => output_enable_PCL_ADL,
            signal_1_PC => signal_I_PC,
            signal_PCL_PCL => load_PCLS_from_PCL,
            signal_ADL_PCL => load_PCLS_from_ADL,
            signal_PCLC => signal_PCLC,
            bus_ADL_in => bus_ADL,
            bus_ADL_out => PCL_ADL,
            bus_DB => PCL_DB,
            metaclock => metaclock
        );
    load_PCHS_from_PCH <= load_PCH_PCH and phi1;
    load_PCHS_from_ADH <= load_ADH_PCH and phi1;
    PCH: program_counter_high
        port map(
            phi2 => phi2,
            signal_PCH_DB => output_enable_PCH_DB,
            signal_PCH_ADH => output_enable_PCH_ADH,
            signal_PCLC => signal_PCLC,
            signal_PCH_PCH => load_PCHS_from_PCH,
            signal_ADH_PCH => load_PCHS_from_ADH,
            bus_ADH_in => bus_ADH,
            bus_ADH_out => PCH_ADH,
            bus_DB => PCH_DB,
            metaclock => metaclock
        );
end architecture;
