library ieee;
use ieee.std_logic_1164.all;

entity adder_hold_register is
    port(
        --! Load signal for the register from the data input
        --! Should be wired to the clock generator Phi2 output
        load: std_ulogic;
        --! The data to be loaded into the register
        data_in: std_ulogic_vector(7 downto 0);
        --! @ref Ricoh2A03_ADD_SB
        sb_bus_enable_ADD_SB: in std_ulogic;
        --! Port for the SB bus of the MOS 6502
        sb_bus_port: out std_ulogic_vector(7 downto 0);
        --! @ref Ricoh2A03_ADD_ADL
        adh_bus_enable_ADD_ADL: in std_ulogic;
        --! Port for the ADH bus of the MOS 6502
        adh_bus_port: out std_ulogic_vector(7 downto 0)
    );
end entity;

architecture rtl of adder_hold_register is
    signal register_data: std_ulogic_vector(7 downto 0);
begin
    process(load)
    begin
        if rising_edge(load) then
            register_data <= data_in;
        end if;
    end process;

    sb_bus_port <= register_data when sb_bus_enable_ADD_SB = '1' else (others => 'Z');
    adh_bus_port <= register_data when adh_bus_enable_ADD_ADL = '1' else (others => 'Z');
end architecture;