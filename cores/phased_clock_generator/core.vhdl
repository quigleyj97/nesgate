library ieee;
use ieee.std_logic_1164.all;

entity phased_clock_generator is
    port(
        clk_in: in std_ulogic;
        clk_phi1: inout std_ulogic;
        clk_phi2: inout std_ulogic
    );
end entity;

architecture rtl of phased_clock_generator is
begin
    clk_phi1 <= clk_in nor clk_phi2;
    clk_phi2 <= clk_in and not clk_phi1;
end rtl;
