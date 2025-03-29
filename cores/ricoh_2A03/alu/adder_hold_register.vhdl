library ieee;
use ieee.std_logic_1164.all;

entity adder_hold_register is
    port(
        --! Load signal for the register from the data input
        --! Should be wired to the clock generator Phi2 output
        load: std_ulogic;
        --! The data to be loaded into the register
        data_in: std_ulogic_vector(7 downto 0);
        --! @ref Ricoh2A03_ADD_SB_0_6
        sb_bus_enable_ADD_SB_0_6: in std_ulogic;
        --! @ref Ricoh2A03_ADD_SB_7
        sb_bus_enable_ADD_SB_7: in std_ulogic;
        --! Port for the SB bus of the MOS 6502
        sb_bus_port: out std_ulogic_vector(7 downto 0);
        --! @ref Ricoh2A03_ADD_ADL
        adl_bus_enable_ADD_ADL: in std_ulogic;
        --! Port for the ADL bus of the MOS 6502
        adl_bus_port: out std_ulogic_vector(7 downto 0)
    );
end entity;

architecture rtl of adder_hold_register is
    signal register_data: std_ulogic_vector(7 downto 0) := (others => '0');
begin
    process(load, data_in)
    begin
        if load'event and load = '1' then
            register_data <= data_in;
        end if;
    end process;

    sb_bus_port(6 downto 0) <= register_data(6 downto 0) when sb_bus_enable_ADD_SB_0_6 = '1' else (others => 'Z');
    sb_bus_port(7) <= register_data(7) when sb_bus_enable_ADD_SB_7 = '1' else 'Z';
    adl_bus_port <= register_data when adl_bus_enable_ADD_ADL = '1' else (others => 'Z');
end architecture;