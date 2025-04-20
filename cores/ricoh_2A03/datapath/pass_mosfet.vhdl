--! @file
--! @brief Pass MOSFET component that connects two buses when enabled
--! @details This component models a pass MOSFET that connects two buses when enabled
--! and isolates them when disabled.

library ieee;
use ieee.std_logic_1164.all;

--! @brief Pass MOSFET entity that connects or isolates two 8-bit buses
entity pass_mosfet is
  port (
    --! @ref Control_Enable Enable signal that connects the buses when asserted
    enable : in std_ulogic;
    
    --! @ref Data_Bus_1 First 8-bit bus
    bus_1  : inout std_ulogic_vector(7 downto 0);
    
    --! @ref Data_Bus_2 Second 8-bit bus
    bus_2  : inout std_ulogic_vector(7 downto 0)
  );
end entity pass_mosfet;

--! @brief RTL architecture for pass_mosfet
--! @details When enable is asserted, bus_1 and bus_2 are electrically connected.
--! When enable is not asserted, the buses are electrically isolated.
architecture rtl of pass_mosfet is
begin
  -- Simply connect the buses in both directions when enabled
  -- When disabled, both buses are set to high impedance
  bus_1 <= bus_2 when enable = '1' else (others => 'Z');
  bus_2 <= bus_1 when enable = '1' else (others => 'Z');
end architecture rtl;