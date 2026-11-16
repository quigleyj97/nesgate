library ieee;
use ieee.std_logic_1164.all;

-- The Stack Pointer register from the MOS 6502 CPU
entity stack_pointer is
    port(
        --! @ref Ricoh_2A03_Signal_S_SB
        signal_S_SB: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_S_ADL
        signal_S_ADL: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_SB_S
        signal_SB_S: in std_ulogic;
        --! @ref Ricoh_2A03_SB, as resolved by @ref bus_multiplexer
        bus_SB_in: in std_ulogic_vector(7 downto 0);
        --! Drives @ref Ricoh_2A03_SB, 'Z' when not enabled
        bus_SB_out: out std_ulogic_vector(7 downto 0);
        --! Drives @ref Ricoh_2A03_ADL, 'Z' when not enabled
        bus_ADL: out std_ulogic_vector(7 downto 0);
        --! Clock to drive the latch circuitry
        --! @ref metaclock
        metaclock: in std_ulogic
    );
end entity stack_pointer;

architecture rtl of stack_pointer is
    signal register_value: std_ulogic_vector(7 downto 0) := (others => '0');
begin
    process(metaclock)
    begin
        if rising_edge(metaclock) then
            if signal_SB_S = '1' then
                register_value <= bus_SB_in;
            end if;
        end if;
    end process;
    bus_SB_out <= register_value when signal_S_SB = '1' else (others => 'Z');
    bus_ADL <= register_value when signal_S_ADL = '1' else (others => 'Z');
end architecture rtl;
