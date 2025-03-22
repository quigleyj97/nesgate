library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity mos_6502 is
    port (
        clock: in std_ulogic;
        phi1: in std_ulogic;
        phi2: in std_ulogic;
        address: out std_ulogic_vector(15 downto 0);
        data: inout std_ulogic_vector(7 downto 0);
        superclock: in std_ulogic
    );
end entity;
