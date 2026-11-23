--! @file bus_multiplexer.vhdl
--! @brief Resolves the values of the SB, DB, ADH and ADL buses
--! @details The 6502's internal buses are precharged high during phi2, and
--! keep that charge until something pulls them low. Each subunit that drives
--! a bus can only pull bits low or leave them alone, so a bus behaves as a
--! wired-AND with a default of all ones. The open drain MOSFETs pull bits of
--! ADL and ADH low to form the interrupt vectors and zero page addresses, and
--! the pass MOSFETs (SB/DB, SB/ADH) join SB and DB or ADH into a single node.
--!
--! Modelling this with 'Z' drivers on shared signals doesn't work. In
--! simulation, a '0' and a '1' on the same signal resolve to 'X', and in
--! synthesis, yosys can only merge several tri-state drivers into a mux, not a
--! wired-AND. Instead, a subunit that isn't driving a bus drives all ones (the
--! precharge level), the datapath ANDs every subunit's driver of a bus into one
--! `drive_*` input, and this entity computes the value that every subunit
--! reads back:
--!
--! - a bit nothing pulls low reads '1', as if still precharged;
--! - a bit any connected driver or open drain MOSFET pulls low reads '0';
--! - SB/DB and SB/ADH merge the buses they connect, so every bus in the
--!   group reads the same value.
--!
--! There's no need to model the precharge per phase: the buses are
--! precharged every phi2, and hold their charge through phi1.

library ieee;
use ieee.std_logic_1164.all;

entity bus_multiplexer is
    port(
        -- #region Bus drivers
        --! Everything driving @ref MOS_6502_SB, ANDed together. All ones
        --! where nothing pulls it low.
        drive_SB: in std_ulogic_vector(7 downto 0);
        --! Everything driving @ref MOS_6502_DB, ANDed together
        drive_DB: in std_ulogic_vector(7 downto 0);
        --! Everything driving @ref MOS_6502_ADH, ANDed together
        drive_ADH: in std_ulogic_vector(7 downto 0);
        --! Everything driving @ref MOS_6502_ADL, ANDed together
        drive_ADL: in std_ulogic_vector(7 downto 0);
        -- #endregion

        -- #region Pass MOSFETs
        --! @ref MOS_6502_Signal_SB_DB
        connect_SB_DB: in std_ulogic;
        --! @ref MOS_6502_Signal_SB_ADH
        connect_SB_ADH: in std_ulogic;
        -- #endregion

        -- #region Open drain MOSFETs
        --! @ref MOS_6502_Signal_0_ADL0
        clear_0_ADL0: in std_ulogic;
        --! @ref MOS_6502_Signal_0_ADL1
        clear_0_ADL1: in std_ulogic;
        --! @ref MOS_6502_Signal_0_ADL2
        clear_0_ADL2: in std_ulogic;
        --! @ref MOS_6502_Signal_0_ADH0
        clear_0_ADH0: in std_ulogic;
        --! @ref MOS_6502_Signal_0_ADH_1_7
        clear_0_ADH_1_7: in std_ulogic;
        -- #endregion

        -- #region Bus values
        --! @ref MOS_6502_SB
        bus_SB: out std_ulogic_vector(7 downto 0);
        --! @ref MOS_6502_DB
        bus_DB: out std_ulogic_vector(7 downto 0);
        --! @ref MOS_6502_ADH
        bus_ADH: out std_ulogic_vector(7 downto 0);
        --! @ref MOS_6502_ADL
        bus_ADL: out std_ulogic_vector(7 downto 0)
        -- #endregion
    );
end entity;

architecture rtl of bus_multiplexer is
    --! A bus that a pass MOSFET can join to SB, or all ones (the identity for
    --! a wired-AND) when the pass MOSFET is off.
    function joined(level: std_ulogic_vector; connect: std_ulogic) return std_ulogic_vector is
    begin
        if connect = '1' then
            return level;
        end if;
        return (level'range => '1');
    end function;

    signal level_SB: std_ulogic_vector(7 downto 0);
    signal level_DB: std_ulogic_vector(7 downto 0);
    signal level_ADH: std_ulogic_vector(7 downto 0);
    signal level_ADL: std_ulogic_vector(7 downto 0);
    --! The single node formed by SB and whichever buses are joined to it
    signal level_SB_group: std_ulogic_vector(7 downto 0);
    signal open_drain_ADH: std_ulogic_vector(7 downto 0);
    signal open_drain_ADL: std_ulogic_vector(7 downto 0);
begin
    -- The open drain MOSFETs pull bits low, so they're ANDed in like any other
    -- driver ('0' to pull low, '1' to leave alone)
    open_drain_ADL <= "11111" & not clear_0_ADL2 & not clear_0_ADL1 & not clear_0_ADL0;
    open_drain_ADH <= (7 downto 1 => not clear_0_ADH_1_7) & not clear_0_ADH0;

    level_SB  <= drive_SB;
    level_DB  <= drive_DB;
    level_ADH <= drive_ADH and open_drain_ADH;
    level_ADL <= drive_ADL and open_drain_ADL;

    level_SB_group <= level_SB
        and joined(level_DB, connect_SB_DB)
        and joined(level_ADH, connect_SB_ADH);

    bus_SB  <= level_SB_group;
    bus_DB  <= level_SB_group when connect_SB_DB = '1' else level_DB;
    bus_ADH <= level_SB_group when connect_SB_ADH = '1' else level_ADH;
    -- No pass MOSFET connects ADL to any other bus
    bus_ADL <= level_ADL;
end architecture;
