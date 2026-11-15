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

--! Placeholder architecture, so the entity analyzes and synthesizes.
--! @todo Wire the ALU (logic_core) and datapath (mos_6502_datapath) together,
--! driven by the instruction decoder once it exists. Until then this drives a
--! zero address and leaves the data pins floating.
architecture rtl of mos_6502 is
begin
    address <= (others => '0');
    data <= (others => 'Z');
end architecture;
