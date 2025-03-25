library ieee;
use ieee.std_logic_1164.all;

--! The Accumulator for the 6502
entity accumulator is
    port(
        --! @ref Ricoh_2A03_SB
        --! @todo This does not implement the BCD correction circuitry
        databus_SB: inout std_ulogic_vector(7 downto 0);
        --! @ref Ricoh_2A03_DB
        databus_DB: out std_ulogic_vector(7 downto 0);
        --! @ref Ricoh_Signal_SB_AC
        load_SB_AC: in std_ulogic;
        --! @ref Ricoh_Signal_AC_SB
        output_enable_AC_SB: in std_ulogic;
        --! @ref Ricoh_Signal_AC_DB
        output_enable_AC_DB: in std_ulogic
    );
end entity;

architecture rtl of accumulator is
    signal register_data: std_ulogic_vector(7 downto 0) := (others => '0');
begin
    process(load_SB_AC, databus_SB)
    begin
        if rising_edge(load_SB_AC) then
            register_data <= databus_SB;
        end if;
    end process;

    databus_DB <= register_data when output_enable_AC_DB = '1' else (others => 'Z');
    databus_SB <= register_data when output_enable_AC_SB = '1' else (others => 'Z');
end architecture;
