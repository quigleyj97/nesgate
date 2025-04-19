--! @file
--! @brief Open drain MOSFET for ADL bus
--! Pulls down specific bits of the ADL bus when control signals are asserted

library ieee;
use ieee.std_logic_1164.all;

--! Open drain MOSFET for ADL bus implementation
entity adl_open_drain_mosfet is
  port(
    --! @ref Ricoh_2A03_Signal_0_ADL0
    signal_0_ADL0: in std_ulogic;
    --! @ref Ricoh_2A03_Signal_0_ADL1
    signal_0_ADL1: in std_ulogic;
    --! @ref Ricoh_2A03_Signal_0_ADL2
    signal_0_ADL2: in std_ulogic;
    --! ADL bus output
    adl_bus: out std_ulogic_vector(7 downto 0) := (others => 'Z')
  );
end entity adl_open_drain_mosfet;

architecture rtl of adl_open_drain_mosfet is
begin
  -- Open drain behavior - pull specific bits low when signals are asserted
  adl_bus(0) <= '0' when signal_0_ADL0 = '1' else 'Z';
  adl_bus(1) <= '0' when signal_0_ADL1 = '1' else 'Z';
  adl_bus(2) <= '0' when signal_0_ADL2 = '1' else 'Z';
end architecture rtl;