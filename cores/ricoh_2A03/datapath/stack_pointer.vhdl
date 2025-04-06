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
        --! @ref Ricoh_2A03_SB
        bus_SB: inout std_logic_vector(7 downto 0);
        --! @ref Ricoh_2A03_ADL
        bus_ADL: out std_logic_vector(7 downto 0)
    );
end entity stack_pointer;

architecture rtl of stack_pointer is
    signal register_value: std_logic_vector(7 downto 0);
begin
    process(signal_SB_S, bus_SB)
    begin
        if signal_SB_S = '1' then
            register_value <= bus_SB;
        else
            register_value <= register_value;
        end if;
    end process;
    bus_SB <= register_value when signal_S_SB = '1' else (others => 'Z');
    bus_ADL <= register_value when signal_S_ADL = '1' else (others => 'Z');
end architecture rtl;
