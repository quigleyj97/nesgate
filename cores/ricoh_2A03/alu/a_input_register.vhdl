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
        data_out: out std_ulogic_vector(7 downto 0)
    );
end entity;

architecture rtl of a_input_register is
    signal data_register: std_ulogic_vector(7 downto 0) := (others => '0');
begin
    process(clear_0_ADD, load_SB_ADD)
    begin
        if (clear_0_ADD = '1') and (load_SB_ADD = '0') then
            data_register <= (others => '0');
        elsif (clear_0_ADD = '0') and (load_SB_ADD = '1') then
            data_register <= data_in_SB;
        elsif (clear_0_ADD = '1') and (load_SB_ADD = '1') then
            data_register <= (others => '-');
        else
            data_register <= data_register;
        end if;
    end process;
    data_out <= data_register;
end architecture;