--! Wrapper component holding the data input/output latches,
--! the index registers, the address registers, and the status register.
--! TODO: Add precharge and drain MOSFETs
entity mos_6502_datapath is
    port(
        --! The external-facing data pins
        data: inout std_ulogic_vector(7 downto 0);
        --! The external-facing address pins
        address: inout std_ulogic_vector(15 downto 0);
        --! @ref Ricoh_2A03_PHI1
        phi1: in std_ulogic;
        --! @ref Ricoh_2A03_PHI2
        phi2: in std_ulogic;

        -- #region Databus
        --! @ref Ricoh_2A03_SB
        databus_SB: inout std_ulogic_vector(7 downto 0);
        --! @ref Ricoh_2A03_DB
        databus_DB: out std_ulogic_vector(7 downto 0);
        --! @ref Ricoh_2A03_ADH
        databus_ADH: out std_ulogic_vector(7 downto 0);
        --! @ref Ricoh_2A03_ADL
        databus_ADL: out std_ulogic_vector(7 downto 0);
        -- #endregion

        -- #region Control signals

        --! @ref Ricoh_Signal_SB_AC
        load_SB_AC: in std_ulogic;
        --! @ref Ricoh_Signal_AC_SB
        output_enable_AC_SB: in std_ulogic;
        --! @ref Ricoh_Signal_AC_DB
        output_enable_AC_DB: in std_ulogic
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
    signal load_ABH: std_ulogic;
    signal load_ABL: std_ulogic;
begin
    ACC: accumulator
        port map(
            databus_SB => databus_SB,
            databus_DB => databus_DB,
            load_SB_AC => load_SB_AC,
            output_enable_AC_SB => output_enable_AC_SB,
            output_enable_AC_DB => output_enable_AC_DB
        );
    X_REG: index_register
        port map(
            data_in => databus_SB,
            load => signal_SB_X,
            data_out => databus_SB,
            output_enable => signal_X_SB
        );
    Y_REG: index_register
        port map(
            data_in => databus_SB,
            load => signal_SB_Y,
            data_out => databus_SB,
            output_enable => signal_Y_SB
        );
    STATUS_REGISTER: status_register
        port map(
            db_bus => databus_DB,
            enable_P_DB => signal_P_DB,
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
    load_ABH <= signal_ADH_ABH and phi1;
    ABH_REG: index_register
        port map(
            data_in => databus_ADH,
            load => signal_ADH,
            data_out => address(15 downto 8),
            output_enable => '1'
        );
    load_ABL <= signal_ADL_ABL and phi1;
    ABL_REG: index_register
        port map(
            data_in => databus_ADL,
            load => signal_ADL,
            data_out => address(7 downto 0),
            output_enable => '1'
        );
    DATA_INPUT_LATCH: data_input_latch
        port map(
            load => phi2,
            data_in => data,
            db_bus_enable_DL_DB => signal_DL_DB,
            db_bus_port => databus_DB,
            adh_bus_enable_DL_ADH => signal_DL_ADH,
            adh_bus_port => databus_ADH,
            adl_bus_enable_DL_ADL => signal_DL_ADL,
            adl_bus_port => databus_ADL
        );
    DATA_OUTPUT_LATCH: data_output_latch
        port map(
            phi1 => phi1,
            phi2 => phi2,
            signal_R_NOT_W => signal_R_NOT_W,
            data_in => databus_DB,
            data_out => data
        );
end architecture;
