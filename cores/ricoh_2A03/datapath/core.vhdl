--! @file core.vhdl
--! @brief Wrapper component holding the data input/output latches, the
--! accumulator and index registers, the address registers, and the status
--! register.
--! @details The internal buses (SB, DB, ADH, ADL) are driven by several
--! subunits at once, each releasing the bus to 'Z' when it isn't enabled.
--! An unresolved std_ulogic_vector can only have one driver, so the bus ports
--! here are resolved std_logic_vectors, and each subunit's std_ulogic_vector
--! ports are converted at the port map.
--! @todo Add the stack pointer, program counter, and precharge and drain MOSFETs

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

        -- #region Buses
        --! @ref Ricoh_2A03_SB
        databus_SB: inout std_logic_vector(7 downto 0);
        --! @ref Ricoh_2A03_DB
        databus_DB: inout std_logic_vector(7 downto 0);
        --! @ref Ricoh_2A03_ADH
        databus_ADH: inout std_logic_vector(7 downto 0);
        --! @ref Ricoh_2A03_ADL
        databus_ADL: inout std_logic_vector(7 downto 0);
        -- #endregion

        -- #region Control signals

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

        -- Address bus registers
        --! @ref Ricoh_2A03_Signal_ADH_ABH
        load_ADH_ABH: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_ADL_ABL
        load_ADL_ABL: in std_ulogic;

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
    component accumulator is
        port(
            databus_SB: inout std_ulogic_vector(7 downto 0);
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
            db_bus: inout std_ulogic_vector(7 downto 0);
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
    -- #endregion

    for ACC: accumulator use entity work.accumulator;
    for X_REG, Y_REG, ABH_REG, ABL_REG: index_register use entity work.index_register;
    for P_REG: status_register use entity work.status_register;
    for DL: data_input_latch use entity work.data_input_latch;
    for DOR: data_output_latch use entity work.data_output_latch;

    --! The address bus registers load from ADH/ADL during phi1
    signal load_ABH: std_ulogic;
    signal load_ABL: std_ulogic;
begin
    ACC: accumulator
        port map(
            std_logic_vector(databus_SB) => std_ulogic_vector(databus_SB),
            std_logic_vector(databus_DB) => databus_DB,
            load_SB_AC => load_SB_AC,
            output_enable_AC_SB => output_enable_AC_SB,
            output_enable_AC_DB => output_enable_AC_DB
        );
    X_REG: index_register
        port map(
            data_in => std_ulogic_vector(databus_SB),
            load => load_SB_X,
            std_logic_vector(data_out) => databus_SB,
            output_enable => output_enable_X_SB
        );
    Y_REG: index_register
        port map(
            data_in => std_ulogic_vector(databus_SB),
            load => load_SB_Y,
            std_logic_vector(data_out) => databus_SB,
            output_enable => output_enable_Y_SB
        );
    P_REG: status_register
        port map(
            std_logic_vector(db_bus) => std_ulogic_vector(databus_DB),
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
            data_in => std_ulogic_vector(databus_ADH),
            load => load_ABH,
            data_out => address(15 downto 8),
            output_enable => '1'
        );
    load_ABL <= load_ADL_ABL and phi1;
    ABL_REG: index_register
        port map(
            data_in => std_ulogic_vector(databus_ADL),
            load => load_ABL,
            data_out => address(7 downto 0),
            output_enable => '1'
        );
    DL: data_input_latch
        port map(
            load => phi2,
            data_in => data,
            db_bus_enable_DL_DB => output_enable_DL_DB,
            std_logic_vector(db_bus_port) => databus_DB,
            adh_bus_enable_DL_ADH => output_enable_DL_ADH,
            std_logic_vector(adh_bus_port) => databus_ADH,
            adl_bus_enable_DL_ADL => output_enable_DL_ADL,
            std_logic_vector(adl_bus_port) => databus_ADL
        );
    DOR: data_output_latch
        port map(
            phi1 => phi1,
            phi2 => phi2,
            signal_R_NOT_W => signal_R_NOT_W,
            data_in => std_ulogic_vector(databus_DB),
            data_out => data
        );
end architecture;
