--! @file precharge_mosfets.vhdl
--! @brief Precharge MOSFETs for internal buses
--! 
--! This block implements the bus precharging behavior for the 6502.
--! When phi2 is asserted, all bits of the bus are pulled high.

library IEEE;
use IEEE.std_logic_1164.all;

--! @brief Precharge MOSFET component for bus precharging
entity precharge_mosfets is
    port(
        phi2 : in std_ulogic; --! @ref Ricoh_2A03_Phi2
        databus : out std_ulogic_vector(7 downto 0) --! The bus to precharge
    );
end entity;

--! @brief RTL implementation of precharge_mosfets
architecture rtl of precharge_mosfets is
begin
    -- When phi2 is high, precharge the bus by setting all bits high
    -- Otherwise, the bus is in high impedance state (disconnected)
    databus <= (others => '1') when phi2 = '1' else (others => 'Z');
end architecture;