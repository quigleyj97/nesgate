library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity mos_6502 is
    port (
        clock: in std_ulogic;
        address: out std_ulogic_vector(15 downto 0);
        data: inout std_ulogic_vector(7 downto 0)
    );
end entity;

architecture rtl of mos_6502 is
    component mos_6502_alu
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
    component a_input_register
    port (
        load_SB_ADD: in std_ulogic;
        data_in_SB: in std_ulogic_vector(7 downto 0);
        clear_0_ADD: in std_ulogic;
        data_out: out std_ulogic_vector(7 downto 0);
        phi2: in std_ulogic
    );
    end component;
    component adder_hold_register
    port (
        load: in std_ulogic;
        data_in: in std_ulogic_vector(7 downto 0);
        sb_bus_enable_ADD_SB: in std_ulogic;
        sb_bus_port: out std_ulogic_vector(7 downto 0);
        adh_bus_enable_ADD_ADL: in std_ulogic;
        adh_bus_port: out std_ulogic_vector(7 downto 0)
    );
    end component;

    for alu0: mos_6502_alu use entity work.mos_6502_alu;
    for a_input_register0: a_input_register use entity work.a_input_register;
    for adder_hold_register0: adder_hold_register use entity work.adder_hold_register;
    signal a_input_register_data_out: std_ulogic_vector(7 downto 0) := (others => '0');
    signal alu_result: std_ulogic_vector(7 downto 0) := (others => '0');
    signal adh_bus: std_ulogic_vector(7 downto 0) := (others => '0');
    signal alu_carry_out_ACR: std_ulogic;
    signal alu_overflow_AVR: std_ulogic;
    signal alu_half_carry_HC: std_ulogic;
    signal sb_bus: std_ulogic_vector(7 downto 0) := (others => '0');

    signal phi1: std_ulogic := '0';
    signal phi2: std_ulogic := '0';
begin
    phi1 <= clock;
    phi2 <= not clock;
    alu0: mos_6502_alu port map(
        a => a_input_register_data_out,
        b => "00000001",
        result => alu_result,
        carry_out_ACR => alu_carry_out_ACR,
        overflow_AVR => alu_overflow_AVR,
        half_carry_HC => alu_half_carry_HC,
        decimal_enable_DAA => '0',
        carry_in_IADDC => '0',
        enable_sum_SUMS => '1',
        enable_and_ANDS => '0',
        enable_xor_EORS => '0',
        enable_or_ORS => '0',
        enable_right_shift_SRS => '0'
    );
    adder_hold_register0: adder_hold_register port map(
        load => phi2,
        data_in => alu_result,
        sb_bus_enable_ADD_SB => '1',
        sb_bus_port => sb_bus,
        adh_bus_enable_ADD_ADL => '0',
        adh_bus_port => adh_bus
    );
    a_input_register0: a_input_register port map(
        load_SB_ADD => '1',
        data_in_SB => sb_bus,
        clear_0_ADD => '0',
        data_out => a_input_register_data_out,
        phi2 => phi2
    );

    data <= sb_bus;
    address <= "0000000000000000";
end architecture;