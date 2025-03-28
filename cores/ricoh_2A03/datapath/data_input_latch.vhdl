library ieee;
use ieee.std_logic_1164.all;

--! Data input latch for the Ricoh 2A03, connected to the DB, ADL, and ADH buses
entity data_input_latch is
    port(
        --! Load signal for the register from the data input
        --! Should be wired to the clock generator Phi2 output
        load: in std_ulogic;
        --! The data to be loaded into the register, maps to D0-D7
        data_in: in std_ulogic_vector(7 downto 0);
        --! @ref Ricoh_2A03_Signal_DL_DB
        db_bus_enable_DL_DB: in std_ulogic;
        --! @ref Ricoh_2A03_DB
        db_bus_port: out std_ulogic_vector(7 downto 0);
        --! @ref Ricoh_2A03_Signal_DL_ADH
        adh_bus_enable_DL_ADH: in std_ulogic;
        --! @ref Ricoh_2A03_ADH
        adh_bus_port: out std_ulogic_vector(7 downto 0);
        --! @ref Ricoh_2A03_Signal_DL_ADL
        adl_bus_enable_DL_ADL: in std_ulogic;
        --! @ref Ricoh_2A03_ADL
        adl_bus_port: out std_ulogic_vector(7 downto 0)
    );
end entity;

architecture rtl of data_input_latch is
    signal register_data: std_ulogic_vector(7 downto 0) := (others => '0');
begin
    process(load, data_in)
    begin
        if load'event and load = '1' then
            register_data <= data_in;
        end if;
    end process;

    db_bus_port <= register_data when db_bus_enable_DL_DB = '1' else (others => 'Z');
    adh_bus_port <= register_data when adh_bus_enable_DL_ADH = '1' else (others => 'Z');
    adl_bus_port <= register_data when adl_bus_enable_DL_ADL = '1' else (others => 'Z');
end architecture;