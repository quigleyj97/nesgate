library ieee;
use ieee.std_logic_1164.all;

entity toplevel is
    port (
        clk_25mhz: in std_ulogic;
        led: out std_ulogic_vector(0 to 7)
    );
end entity;

architecture rtl of toplevel is
    component blinky
    generic (
        -- 25 MHz onboard clock to 25 Hz
        divide_by: natural := 1000000
    );
    port (
        clk: in std_ulogic;
        led: out std_ulogic_vector(0 to 7)
    );
    end component;

    for blinky0: blinky use entity work.blinky;
begin
    blinky0: blinky port map (
        clk => clk_25mhz,
        led => led
    );
end rtl;
