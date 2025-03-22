library ieee;
use ieee.std_logic_1164.all;

entity toplevel is
    port (
        clk_25mhz: in std_ulogic;
        led: out std_ulogic_vector(7 downto 0);
        btn: in std_ulogic_vector(6 downto 0)
    );
end entity;

architecture rtl of toplevel is
    component alu port (
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

    component a_input_register is
        port(
            load_SB_ADD: in std_ulogic;
            data_in_SB: in std_ulogic_vector(7 downto 0);
            clear_0_ADD: in std_ulogic;
            data_out: out std_ulogic_vector(7 downto 0);
            phi2: in std_ulogic
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

    for alu0: alu use entity work.mos_6502_alu;
    for add0: adder_hold_register use entity work.adder_hold_register;
    for ai0: a_input_register use entity work.a_input_register;
    
    signal databus: std_ulogic_vector(7 downto 0) := (others => '0');
    signal alu_output: std_ulogic_vector(7 downto 0) := (others => '0');
    signal alu_input_a: std_ulogic_vector(7 downto 0) := (others => '0');

    signal clk_slow: std_ulogic := '0';
    signal my_data: std_ulogic_vector(7 downto 0) := (others => '1');

    component clock_divider
    generic(
        -- 25hz
        divide_by: integer := 1000000
    );
    port (
        clk: in std_ulogic;
        clk_out: out std_ulogic
    );
    end component;
    component phased_clock_generator
    port(
        clk_in: in std_ulogic;
        clk_out: out std_ulogic;
        clk_phi1: out std_ulogic;
        clk_phi2: out std_ulogic
    );
    end component;
    for clock_divider_instance: clock_divider use entity work.clock_divider;
    for clock_generator: phased_clock_generator use entity work.phased_clock_generator;
    signal phi0: std_ulogic := '0';
    signal phi1: std_ulogic := '1';
    signal phi2: std_ulogic := '0';

begin
    ai0: a_input_register port map(
        load_SB_ADD => phi2,
        data_in_SB => databus,
        clear_0_ADD => btn(4),
        data_out => alu_input_a,
        phi2 => phi2
    );
    add0: adder_hold_register port map(
        load => phi2,
        data_in => alu_output,
        sb_bus_enable_ADD_SB => '1',
        sb_bus_port => databus,
        adh_bus_enable_ADD_ADL => '1',
        adh_bus_port => led
    );
    alu0: alu port map(
        a => alu_input_a,
        b => "00000001",
        result => alu_output,
        decimal_enable_DAA => '0',
        carry_in_IADDC => '0',
        enable_sum_SUMS => '1',
        enable_and_ANDS => '0',
        enable_xor_EORS => '0',
        enable_or_ORS => '0',
        enable_right_shift_SRS => '0'
    );
    clock_generator: phased_clock_generator port map(
        clk_in => clk_slow,
        clk_out => phi0,
        clk_phi1 => phi1,
        clk_phi2 => phi2
    );
    clock_divider_instance: clock_divider port map (
        clk => clk_25mhz,
        clk_out => clk_slow
    );
end rtl;
