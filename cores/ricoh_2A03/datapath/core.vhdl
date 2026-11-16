--! @file core.vhdl
--! @brief Wrapper component holding the data input/output latches, the
--! accumulator and index registers, the address registers, the program
--! counter, the stack pointer, the status register, and the bus multiplexer.
--! @details The internal buses (SB, DB, ADH, ADL) are driven by several
--! subunits at once, each releasing the bus to 'Z' when it isn't enabled.
--! Each bus has a resolved std_logic_vector driver signal (drivers_*) that
--! every subunit driving it is connected to, converting its std_ulogic_vector
--! port at the port map. The @ref bus_multiplexer then resolves the drivers
--! into the bus values (bus_*) that every subunit reads, applying the
--! precharge, the open drain MOSFETs and the pass MOSFETs.

library ieee;
use ieee.std_logic_1164.all;

entity mos_6502_datapath is
    port(
        --! The external-facing data pins
        data: inout std_ulogic_vector(7 downto 0);
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
        --! ALU's adder hold register), 'Z' when not driving
        drive_SB: in std_ulogic_vector(7 downto 0);
        --! Drives @ref Ricoh_2A03_DB from outside the datapath, 'Z' when not
        --! driving
        drive_DB: in std_ulogic_vector(7 downto 0);
        --! Drives @ref Ricoh_2A03_ADH from outside the datapath, 'Z' when not
        --! driving
        drive_ADH: in std_ulogic_vector(7 downto 0);
        --! Drives @ref Ricoh_2A03_ADL from outside the datapath (e.g. the
        --! ALU's adder hold register), 'Z' when not driving
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
        --! @ref Ricoh_Signal_DB7_N
        signal_DB7_N: in std_ulogic
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
            external_SB: in std_ulogic_vector(7 downto 0);
            external_DB: in std_ulogic_vector(7 downto 0);
            external_ADH: in std_ulogic_vector(7 downto 0);
            external_ADL: in std_ulogic_vector(7 downto 0);
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
            output_enable_AC_DB: in std_ulogic
        );
    end component;
    component index_register is
        port(
            data_in: in std_ulogic_vector(7 downto 0);
            load: in std_ulogic;
            data_out: out std_ulogic_vector(7 downto 0);
            output_enable: in std_ulogic
        );
    end component;
    component stack_pointer is
        port(
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
            adl_bus_port: out std_ulogic_vector(7 downto 0)
        );
    end component;
    component data_output_latch is
        port(
            phi1: in std_ulogic;
            phi2: in std_ulogic;
            signal_R_NOT_W: in std_ulogic;
            data_in: in std_ulogic_vector(7 downto 0);
            data_out: out std_ulogic_vector(7 downto 0)
        );
    end component;
    component status_register is
        port(
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
            signal_DB7_N: in std_ulogic
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
    --! Everything driving each bus. These have several drivers, so they're
    --! resolved std_logic_vectors.
    signal drivers_SB: std_logic_vector(7 downto 0);
    signal drivers_DB: std_logic_vector(7 downto 0);
    signal drivers_ADH: std_logic_vector(7 downto 0);
    signal drivers_ADL: std_logic_vector(7 downto 0);
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
    MUX: bus_multiplexer
        port map(
            drive_SB => std_ulogic_vector(drivers_SB),
            drive_DB => std_ulogic_vector(drivers_DB),
            drive_ADH => std_ulogic_vector(drivers_ADH),
            drive_ADL => std_ulogic_vector(drivers_ADL),
            external_SB => drive_SB,
            external_DB => drive_DB,
            external_ADH => drive_ADH,
            external_ADL => drive_ADL,
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
            std_logic_vector(databus_SB_out) => drivers_SB,
            std_logic_vector(databus_DB) => drivers_DB,
            load_SB_AC => load_SB_AC,
            output_enable_AC_SB => output_enable_AC_SB,
            output_enable_AC_DB => output_enable_AC_DB
        );
    X_REG: index_register
        port map(
            data_in => bus_SB,
            load => load_SB_X,
            std_logic_vector(data_out) => drivers_SB,
            output_enable => output_enable_X_SB
        );
    Y_REG: index_register
        port map(
            data_in => bus_SB,
            load => load_SB_Y,
            std_logic_vector(data_out) => drivers_SB,
            output_enable => output_enable_Y_SB
        );
    S_REG: stack_pointer
        port map(
            signal_S_SB => output_enable_S_SB,
            signal_S_ADL => output_enable_S_ADL,
            signal_SB_S => load_SB_S,
            bus_SB_in => bus_SB,
            std_logic_vector(bus_SB_out) => drivers_SB,
            std_logic_vector(bus_ADL) => drivers_ADL,
            metaclock => metaclock
        );
    P_REG: status_register
        port map(
            db_bus_in => bus_DB,
            std_logic_vector(db_bus_out) => drivers_DB,
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
            signal_DB7_N => signal_DB7_N
        );
    load_ABH <= load_ADH_ABH and phi1;
    ABH_REG: index_register
        port map(
            data_in => bus_ADH,
            load => load_ABH,
            data_out => address(15 downto 8),
            output_enable => '1'
        );
    load_ABL <= load_ADL_ABL and phi1;
    ABL_REG: index_register
        port map(
            data_in => bus_ADL,
            load => load_ABL,
            data_out => address(7 downto 0),
            output_enable => '1'
        );
    DL: data_input_latch
        port map(
            load => phi2,
            data_in => data,
            db_bus_enable_DL_DB => output_enable_DL_DB,
            std_logic_vector(db_bus_port) => drivers_DB,
            adh_bus_enable_DL_ADH => output_enable_DL_ADH,
            std_logic_vector(adh_bus_port) => drivers_ADH,
            adl_bus_enable_DL_ADL => output_enable_DL_ADL,
            std_logic_vector(adl_bus_port) => drivers_ADL
        );
    DOR: data_output_latch
        port map(
            phi1 => phi1,
            phi2 => phi2,
            signal_R_NOT_W => signal_R_NOT_W,
            data_in => bus_DB,
            data_out => data
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
            std_logic_vector(bus_ADL_out) => drivers_ADL,
            std_logic_vector(bus_DB) => drivers_DB,
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
            std_logic_vector(bus_ADH_out) => drivers_ADH,
            std_logic_vector(bus_DB) => drivers_DB,
            metaclock => metaclock
        );
end architecture;
