library ieee;
use ieee.std_logic_1164.all;

--! The Accumulator for the 6502
--! @details On the real chip, the accumulator is a latch that is open while
--! `SB/AC` is asserted, and keeps the last value it saw on SB. `SB/AC` is
--! cut off during Phi2, so that's the value SB settles to by the end of Phi1.
--! FPGA fabric can't synthesize a level-sensitive latch cleanly, so `SB/AC` is
--! sampled on the @ref metaclock instead, and the register follows SB one
--! metaclock behind while it's asserted.
--! @todo This does not implement the BCD correction circuitry
entity accumulator is
    port(
        --! @ref Ricoh_2A03_SB, as resolved by @ref bus_multiplexer
        databus_SB_in: in std_ulogic_vector(7 downto 0);
        --! Drives @ref Ricoh_2A03_SB, all ones (released) when not enabled
        databus_SB_out: out std_ulogic_vector(7 downto 0);
        --! @ref Ricoh_2A03_DB
        databus_DB: out std_ulogic_vector(7 downto 0);
        --! @ref Ricoh_Signal_SB_AC
        load_SB_AC: in std_ulogic;
        --! @ref Ricoh_Signal_AC_SB
        output_enable_AC_SB: in std_ulogic;
        --! @ref Ricoh_Signal_AC_DB
        output_enable_AC_DB: in std_ulogic;
        --! Clock to drive the latch circuitry
        --! @ref metaclock
        metaclock: in std_ulogic
    );
end entity;

architecture rtl of accumulator is
    signal register_data: std_ulogic_vector(7 downto 0) := (others => '0');
begin
    process(metaclock)
    begin
        if rising_edge(metaclock) then
            if load_SB_AC = '1' then
                register_data <= databus_SB_in;
            end if;
        end if;
    end process;

    databus_DB <= register_data when output_enable_AC_DB = '1' else (others => '1');
    databus_SB_out <= register_data when output_enable_AC_SB = '1' else (others => '1');
end architecture;
