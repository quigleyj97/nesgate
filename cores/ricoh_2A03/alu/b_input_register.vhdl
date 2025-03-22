library ieee;
use ieee.std_logic_1164.all;

entity b_input_register is
    port(
        --! Load an inverted word from the DB bus
        --! @ref Ricoh_2A03_Signal_NOT_DB_ADD
        control_not_db_add: in std_ulogic;
        --! Load a word from the DB bus
        --! @ref Ricoh_2A03_Signal_DB_ADD
        control_db_add: in std_ulogic;
        --! Load a word from the ADL bus
        --! @ref Ricoh_2A03_Signal_ADL_ADD
        control_adl_add: in std_ulogic;
        --! The DB bus port
        data_in_db: in std_ulogic_vector(7 downto 0);
        --! The ADL bus port
        data_in_adl: in std_ulogic_vector(7 downto 0);
        --! The output port
        data_out: out std_ulogic_vector(7 downto 0);
        --! Metaclock
        --! @ref metaclock
        metaclock: in std_ulogic
    );
end entity;

architecture rtl of b_input_register is
    signal data_latch: std_ulogic_vector(7 downto 0) := (others => '0');
begin
    process(metaclock)
    begin
        if rising_edge(metaclock) then
            if (control_not_db_add = '1') then
                data_latch <= not data_in_db;
            elsif (control_db_add = '1') then
                data_latch <= data_in_db;
            elsif (control_adl_add = '1') then
                data_latch <= data_in_adl;
            end if;
        end if;
    end process;
    data_out <= data_latch;
end architecture;