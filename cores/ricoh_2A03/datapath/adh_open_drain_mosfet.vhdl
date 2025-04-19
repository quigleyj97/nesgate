library ieee;
use ieee.std_logic_1164.all;

--! Open drain MOSFET for the ADH bus of the Ricoh 2A03
entity adh_open_drain_mosfet is
    port(
        --! @ref Ricoh_2A03_Signal_0_ADH0
        signal_0_ADH0: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_0_ADH_1_7
        signal_0_ADH_1_7: in std_ulogic;
        --! @ref Ricoh_2A03_ADH
        adh_bus: out std_ulogic_vector(7 downto 0)
    );
end entity;

architecture rtl of adh_open_drain_mosfet is
begin
    -- When signal_0_ADH0 is asserted, bit 0 of ADH bus is pulled low
    adh_bus(0) <= '0' when signal_0_ADH0 = '1' else 'Z';
    
    -- When signal_0_ADH_1_7 is asserted, bits 1-7 of ADH bus are pulled low
    adh_bus(1) <= '0' when signal_0_ADH_1_7 = '1' else 'Z';
    adh_bus(2) <= '0' when signal_0_ADH_1_7 = '1' else 'Z';
    adh_bus(3) <= '0' when signal_0_ADH_1_7 = '1' else 'Z';
    adh_bus(4) <= '0' when signal_0_ADH_1_7 = '1' else 'Z';
    adh_bus(5) <= '0' when signal_0_ADH_1_7 = '1' else 'Z';
    adh_bus(6) <= '0' when signal_0_ADH_1_7 = '1' else 'Z';
    adh_bus(7) <= '0' when signal_0_ADH_1_7 = '1' else 'Z';
end architecture;