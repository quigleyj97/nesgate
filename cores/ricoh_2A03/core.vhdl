library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity mos_6502 is
    port (
        clock: in std_ulogic;
        address: out std_ulogic_vector(15 downto 0);
        data: inout std_ulogic_vector(7 downto 0);
    );
end entity;

architecture rtl of mos_6502 is
    signal register_program_counter: std_ulogic_vector(15 downto 0);
    signal register_x: std_ulogic_vector(7 downto 0);
    signal register_y: std_ulogic_vector(7 downto 0);
begin
    process(clock)
    begin
        if rising_edge(clock) then
            
        end if;
    end process;

    address <= register_program_counter;
end architecture;