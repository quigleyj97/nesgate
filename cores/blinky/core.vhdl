--! A simple test module to assure toolchain functionality while I bootstrap
--! the rest of the project

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity blinky is
    generic (
        -- Use this for easier testing- cocotb can't handle generics
        -- and the ghdl binary does not like handling 25 million clock cycles
        divide_by: natural := 25
    );
    port (
        clk: in std_ulogic := '0';
        led: out std_ulogic_vector(0 to 7) := (others => '0')
    );
end entity;

architecture rtl of blinky is
    component clock_divider
    generic(
        divide_by: natural := divide_by
    );
    port(
        clk: in std_ulogic := '0';
        clk_out: out std_ulogic := '0'
    );
    end component;

    for divider: clock_divider use entity work.clock_divider;  

    signal number: unsigned(0 to 7) := (others => '0');
    signal output_clk: std_ulogic := '0';
begin
    divider: clock_divider port map (
        clk => clk,
        clk_out => output_clk
    );

    process(output_clk)
    begin
        if rising_edge(output_clk) then
            if number = 255 then
                number <= (others => '0');
            else
                number <= number + 1;
            end if;
        end if;
    end process;

    process(number)
    begin
        led <= std_ulogic_vector(number);
    end process;
end rtl;