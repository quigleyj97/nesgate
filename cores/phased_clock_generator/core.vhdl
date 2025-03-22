library ieee;
use ieee.std_logic_1164.all;

--! A simple clock generator that generates two mutually independent clock
--! signals from a single input clock signal.
entity phased_clock_generator is
    port(
        clk_in: in std_ulogic;
        clk_out: out std_ulogic;
        clk_phi1: out std_ulogic;
        clk_phi2: out std_ulogic
    );
end entity;

architecture rtl of phased_clock_generator is
    signal clk_internal: std_ulogic := '0';
begin
    process(clk_in)
    begin
        if rising_edge(clk_in) then
            clk_internal <= not clk_internal;
        end if;
    end process;

    clk_out <= clk_internal;
    clk_phi1 <= not clk_internal;
    clk_phi2 <= clk_internal;
end rtl;
