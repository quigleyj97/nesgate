library ieee;
use ieee.std_logic_1164.all;

entity a_input_register is
    port(
        --! @ref Ricoh2A03_SB_ADD
        load_SB_ADD: in std_ulogic;
        --! Data input via the SB bus
        data_in_SB: in std_ulogic_vector(7 downto 0);
        --! @ref Ricoh2A03_0_ADD
        clear_0_ADD: in std_ulogic;
        --! Data output into the ALU
        data_out: out std_ulogic_vector(7 downto 0);
        --! Clock to drive the latch circuitry
        --! @ref metaclock
        metaclock: in std_ulogic
    );
end entity;

architecture rtl of a_input_register is
    signal data_latch: std_ulogic_vector(7 downto 0) := (others => '0');
begin
    process(metaclock)
    begin
        if rising_edge(metaclock) then
            if (load_SB_ADD = '1') then
                data_latch <= data_in_SB;
            elsif (clear_0_ADD = '1') then
                data_latch <= (others => '0');
            end if;
        end if;
    end process;
    data_out <= data_latch;
end architecture;