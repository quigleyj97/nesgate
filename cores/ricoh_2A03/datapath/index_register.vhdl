library ieee;
use ieee.std_logic_1164.all;

--! @brief Index register for the Ricoh 2A03
--! Can model any one-output, one-input CPU register
entity index_register is
    port(
        data_in: in std_ulogic_vector(7 downto 0);
        load: in std_ulogic;
        data_out: out std_ulogic_vector(7 downto 0);
        output_enable: in std_ulogic
    );
end entity;

architecture rtl of index_register is
    signal register_data: std_ulogic_vector(7 downto 0) := (others => '0');
begin
    process(load, data_in)
    begin
        if rising_edge(load) then
            register_data <= data_in;
        end if;
    end process;

    data_out <= register_data when output_enable = '1' else (others => 'Z');
end architecture;