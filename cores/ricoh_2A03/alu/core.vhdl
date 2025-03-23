--! The Arithmetic Logic Unit of the 6502, plus the B and A input registers.
--!
--! This file combines all the cores of the ALU into one subunit that can be
--! dropped in to a 6502 core. The internal signal routing is handled by this
--! core to minimize the possibility of signal wiring mistakes in higher level
--! designs, and ideally will be optimized out at synthesis time as there's
--! no real logic in this core itself. All actual logic is implemented in the
--! components that this core references.

library ieee;
use ieee.std_logic_1164.all;

entity logic_core is
    port(
        --! @ref Ricoh_2A03_ADL
        adl_bus: inout std_ulogic_vector(7 downto 0);
        --! @ref Ricoh_2A03_SB
        sb_bus: inout std_ulogic_vector(7 downto 0);
        --! @ref Ricoh_2A03_DB
        db_bus: inout std_ulogic_vector(7 downto 0);

        -- B register control signals
        --! @ref Ricoh_2A03_Signal_NOT_DB_ADD
        control_not_db_add: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_DB_ADD
        control_db_add: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_ADL_ADD
        control_adl_add: in std_ulogic;

        -- A register control signals
        --! @ref Ricoh2A03_SB_ADD
        control_sb_add: in std_ulogic;
        --! @ref Ricoh2A03_0_ADD
        control_0_add: in std_ulogic;

        -- ALU control signals
        --! @ref Ricoh2A03_ALU_DAA
        control_daa: in std_ulogic;
        --! @ref Ricoh2A03_ALU_IADDC
        control_i_addc: in std_ulogic;
        --! @ref Ricoh2A03_ALU_SUMS
        control_sums: in std_ulogic;
        --! @ref Ricoh2A03_ALU_ANDS
        control_ands: in std_ulogic;
        --! @ref Ricoh2A03_ALU_ORS
        control_ors: in std_ulogic;
        --! @ref Ricoh2A03_ALU_EORS
        control_eors: in std_ulogic;
        --! @ref Ricoh2A03_ALU_SRS
        control_srs: in std_ulogic;

        -- ALU output signals
        --! @ref Ricoh2A03_ALU_AVR
        signal_avr: out std_ulogic;
        --! @ref Ricoh2A03_ALU_ACR
        signal_carry: out std_ulogic;
        --! @ref Ricoh2A03_ALU_HC
        signal_hc: out std_ulogic;

        -- Adder hold register control signals
        --! @ref Ricoh2A03_ADD_SB_0_6
        control_add_sb_0_6: in std_ulogic;
        --! @ref Ricoh2A03_ADD_SB_7
        control_add_sb_7: in std_ulogic;
        --! @ref Ricoh2A03_ADD_ADL
        control_add_adl: in std_ulogic;

        --! @ref metaclock
        metaclock: in std_ulogic;

        --! @ref Ricoh2A03_2A03_Phi2
        phi2: in std_ulogic
    );
end entity;

architecture rtl of logic_core is
    component a_input_register is
        port(
            load_SB_ADD: in std_ulogic;
            data_in_SB: in std_ulogic_vector(7 downto 0);
            clear_0_ADD: in std_ulogic;
            data_out: out std_ulogic_vector(7 downto 0);
            metaclock: in std_ulogic
        );
    end component;
    component b_input_register is
        port(
            control_not_db_add: in std_ulogic;
            control_db_add: in std_ulogic;
            control_adl_add: in std_ulogic;
            data_in_db: in std_ulogic_vector(7 downto 0);
            data_in_adl: in std_ulogic_vector(7 downto 0);
            data_out: out std_ulogic_vector(7 downto 0);
            metaclock: in std_ulogic
        );
    end component;
    component mos_6502_alu is
        port (
            a: in std_ulogic_vector(7 downto 0);
            b: in std_ulogic_vector(7 downto 0);
            result: out std_ulogic_vector(7 downto 0);
            carry_out_ACR: out std_ulogic;
            overflow_AVR: out std_ulogic;
            half_carry_HC: out std_ulogic;
            decimal_enable_DAA: in std_ulogic;
            carry_in_IADDC: in std_ulogic;
            enable_sum_SUMS: in std_ulogic;
            enable_and_ANDS: in std_ulogic;
            enable_xor_EORS: in std_ulogic;
            enable_or_ORS: in std_ulogic;
            enable_right_shift_SRS: in std_ulogic
        );
    end component;
    component adder_hold_register is
        port(
            load: std_ulogic;
            data_in: std_ulogic_vector(7 downto 0);
            sb_bus_enable_ADD_SB: in std_ulogic;
            sb_bus_port: out std_ulogic_vector(7 downto 0);
            adh_bus_enable_ADD_ADL: in std_ulogic;
            adh_bus_port: out std_ulogic_vector(7 downto 0)
        );
    end component;

    signal a_input_data: std_ulogic_vector(7 downto 0) := (others => '0');
    signal b_input_data: std_ulogic_vector(7 downto 0) := (others => '0');
    signal alu_output: std_ulogic_vector(7 downto 0) := (others => '0');

    for alu0: mos_6502_alu use entity work.mos_6502_alu;
    for add0: adder_hold_register use entity work.adder_hold_register;
    for ai0: a_input_register use entity work.a_input_register;
    for bi0: b_input_register use entity work.b_input_register;
begin
    ai0: a_input_register port map (
        load_SB_ADD => control_sb_add,
        data_in_SB => sb_bus,
        clear_0_ADD => control_0_add,
        data_out => a_input_data,
        metaclock => metaclock
    );
    bi0: b_input_register port map (
        control_not_db_add => control_not_db_add,
        control_db_add => control_db_add,
        control_adl_add => control_adl_add,
        data_in_db => db_bus,
        data_in_adl => adl_bus,
        data_out => b_input_data,
        metaclock => metaclock
    );
    alu0: mos_6502_alu port map (
        a => a_input_data,
        b => b_input_data,
        result => alu_output,
        carry_out_ACR => signal_carry,
        overflow_AVR => signal_avr,
        half_carry_HC => signal_hc,
        decimal_enable_DAA => control_daa,
        carry_in_IADDC => control_i_addc,
        enable_sum_SUMS => control_sums,
        enable_and_ANDS => control_ands,
        enable_xor_EORS => control_eors,
        enable_or_ORS => control_ors,
        enable_right_shift_SRS => control_srs
    );
    add0: adder_hold_register port map (
        load => phi2,
        data_in => alu_output,
        sb_bus_enable_ADD_SB_0_6 => control_add_sb_0_6,
        sb_bus_enable_ADD_SB_7 => control_add_sb_7,
        sb_bus_port => sb_bus,
        adh_bus_enable_ADD_ADL => control_add_adl,
        adh_bus_port => adl_bus
    );
end architecture;