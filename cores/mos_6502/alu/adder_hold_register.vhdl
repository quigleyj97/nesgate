--! @file adder_hold_register.vhdl
--! @brief The adder hold register (ADD) of the MOS 6502 ALU
--! @details On the real chip, the hold register is a transparent latch that's
--! open during Phi2 and holds the ALU's result through the next Phi1, while
--! the A and B input registers load the next operands. Here it's sampled on
--! the @ref metaclock while `load` (Phi2) is high, so it holds the result from
--! the last metaclock edge of Phi2, the same edge as the ACR and AVR latches
--! in @ref logic_core.

library ieee;
use ieee.std_logic_1164.all;

entity adder_hold_register is
    port(
        --! Load signal for the register from the data input, sampled on the
        --! @ref metaclock. Should be wired to Phi2.
        load: std_ulogic;
        --! The data to be loaded into the register
        data_in: std_ulogic_vector(7 downto 0);
        --! @ref MOS6502_ADD_SB_0_6
        sb_bus_enable_ADD_SB_0_6: in std_ulogic;
        --! @ref MOS6502_ADD_SB_7
        sb_bus_enable_ADD_SB_7: in std_ulogic;
        --! Drives @ref MOS_6502_SB, all ones (released) on the bits that
        --! aren't enabled
        sb_bus_port: out std_ulogic_vector(7 downto 0);
        --! @ref MOS6502_ADD_ADL
        adl_bus_enable_ADD_ADL: in std_ulogic;
        --! Drives @ref MOS_6502_ADL, all ones (released) when not enabled
        adl_bus_port: out std_ulogic_vector(7 downto 0);
        --! @ref metaclock
        metaclock: in std_ulogic
    );
end entity;

architecture rtl of adder_hold_register is
    signal register_data: std_ulogic_vector(7 downto 0) := (others => '0');
begin
    process(metaclock)
    begin
        if rising_edge(metaclock) then
            if load = '1' then
                register_data <= data_in;
            end if;
        end if;
    end process;

    sb_bus_port(6 downto 0) <= register_data(6 downto 0) when sb_bus_enable_ADD_SB_0_6 = '1' else (others => '1');
    sb_bus_port(7) <= register_data(7) when sb_bus_enable_ADD_SB_7 = '1' else '1';
    adl_bus_port <= register_data when adl_bus_enable_ADD_ADL = '1' else (others => '1');
end architecture;