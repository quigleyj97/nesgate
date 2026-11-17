--! @file bus_multiplexer.vhdl
--! @brief Resolves the values of the SB, DB, ADH and ADL buses
--! @details The 6502's internal buses are precharged high during phi2, and
--! keep that charge until something pulls them low. Each subunit that drives
--! a bus can only pull bits low or leave them alone, so a bus behaves as a
--! wired-AND with a default of all ones. The open drain MOSFETs pull bits of
--! ADL and ADH low to form the interrupt vectors and zero page addresses, and
--! the pass MOSFETs (SB/DB, SB/ADH) join SB and DB or ADH into a single node.
--!
--! Modelling this with 'Z' drivers on shared signals doesn't work: a
--! bidirectional pass MOSFET holds its own value once the driver releases it,
--! and a strong precharge conflicts with every other driver. Instead, each
--! subunit drives a per-bus driver signal (resolved, 'Z' when not driving),
--! and this entity computes the value that every subunit reads back:
--!
--! - a bit no subunit drives reads '1', as if still precharged;
--! - a bit any connected subunit drives '0' reads '0';
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
        --! Everything driving @ref Ricoh_2A03_SB, 'Z' where nothing does
        drive_SB: in std_ulogic_vector(7 downto 0);
        --! Everything driving @ref Ricoh_2A03_DB, 'Z' where nothing does
        drive_DB: in std_ulogic_vector(7 downto 0);
        --! Everything driving @ref Ricoh_2A03_ADH, 'Z' where nothing does
        drive_ADH: in std_ulogic_vector(7 downto 0);
        --! Everything driving @ref Ricoh_2A03_ADL, 'Z' where nothing does
        drive_ADL: in std_ulogic_vector(7 downto 0);
        --! Drivers of @ref Ricoh_2A03_SB from outside the datapath (e.g. the ALU),
        --! 'Z' where nothing drives. Kept separate from drive_SB so that the
        --! datapath doesn't need to merge an input port with its own tri-state
        --! drivers, which GHDL can't synthesize.
        external_SB: in std_ulogic_vector(7 downto 0);
        --! Drivers of @ref Ricoh_2A03_DB from outside the datapath (e.g. the ALU),
        --! 'Z' where nothing drives. Kept separate from drive_DB so that the
        --! datapath doesn't need to merge an input port with its own tri-state
        --! drivers, which GHDL can't synthesize.
        external_DB: in std_ulogic_vector(7 downto 0);
        --! Drivers of @ref Ricoh_2A03_ADH from outside the datapath (e.g. the ALU),
        --! 'Z' where nothing drives. Kept separate from drive_ADH so that the
        --! datapath doesn't need to merge an input port with its own tri-state
        --! drivers, which GHDL can't synthesize.
        external_ADH: in std_ulogic_vector(7 downto 0);
        --! Drivers of @ref Ricoh_2A03_ADL from outside the datapath (e.g. the ALU),
        --! 'Z' where nothing drives. Kept separate from drive_ADL so that the
        --! datapath doesn't need to merge an input port with its own tri-state
        --! drivers, which GHDL can't synthesize.
        external_ADL: in std_ulogic_vector(7 downto 0);
        -- #endregion

        -- #region Pass MOSFETs
        --! @ref Ricoh_2A03_Signal_SB_DB
        connect_SB_DB: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_SB_ADH
        connect_SB_ADH: in std_ulogic;
        -- #endregion

        -- #region Open drain MOSFETs
        --! @ref Ricoh_2A03_Signal_0_ADL0
        clear_0_ADL0: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_0_ADL1
        clear_0_ADL1: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_0_ADL2
        clear_0_ADL2: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_0_ADH0
        clear_0_ADH0: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_0_ADH_1_7
        clear_0_ADH_1_7: in std_ulogic;
        -- #endregion

        -- #region Bus values
        --! @ref Ricoh_2A03_SB
        bus_SB: out std_ulogic_vector(7 downto 0);
        --! @ref Ricoh_2A03_DB
        bus_DB: out std_ulogic_vector(7 downto 0);
        --! @ref Ricoh_2A03_ADH
        bus_ADH: out std_ulogic_vector(7 downto 0);
        --! @ref Ricoh_2A03_ADL
        bus_ADL: out std_ulogic_vector(7 downto 0)
        -- #endregion
    );
end entity;

architecture rtl of bus_multiplexer is
    --! The level of a precharged bus bit: '0' if it's pulled low, '1' if it's
    --! undriven or driven high. Anything else (a conflict, or an uninitialized
    --! driver) stays 'X' so that it's still visible in simulation.
    function precharged(drive: std_ulogic_vector) return std_ulogic_vector is
        variable level: std_ulogic_vector(drive'range);
    begin
        for i in drive'range loop
            case drive(i) is
                when '0' | 'L' => level(i) := '0';
                when '1' | 'H' | 'Z' => level(i) := '1';
                when others => level(i) := 'X';
            end case;
        end loop;
        return level;
    end function;

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

    level_SB  <= precharged(drive_SB) and precharged(external_SB);
    level_DB  <= precharged(drive_DB) and precharged(external_DB);
    level_ADH <= precharged(drive_ADH) and precharged(external_ADH) and open_drain_ADH;
    level_ADL <= precharged(drive_ADL) and precharged(external_ADL) and open_drain_ADL;

    level_SB_group <= level_SB
        and joined(level_DB, connect_SB_DB)
        and joined(level_ADH, connect_SB_ADH);

    bus_SB  <= level_SB_group;
    bus_DB  <= level_SB_group when connect_SB_DB = '1' else level_DB;
    bus_ADH <= level_SB_group when connect_SB_ADH = '1' else level_ADH;
    -- No pass MOSFET connects ADL to any other bus
    bus_ADL <= level_ADL;
end architecture;
