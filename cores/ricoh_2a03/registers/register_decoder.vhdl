library ieee;
use ieee.std_logic_1164.all;

--! @file
--! @brief The 2A03's register decoder, which turns reads and writes of
--! `$4000`-`$401F` into register strobes
--! @details Decoding happens in two steps:
--!
--! 1. The predecoder checks that the CPU is addressing `$4000`-`$401F`, using
--!    the CPU's own address bus (`CPU_A`), and splits that into a read
--!    (@ref Ricoh_2A03_Signal_REGRD) and a write
--!    (@ref Ricoh_2A03_Signal_REGWR) using the CPU's R/W.
--! 2. A PLA picks the register from the low five bits of the address the
--!    2A03 puts on its pins, which comes from the @ref address_multiplexer
--!    (`A`), not from the CPU.
--!
--! Most of the time the two addresses are the same. But while a DMA owns the
--! address pins, the CPU is stalled on a read, and if that read is of
--! `$4000`-`$401F` the PLA decodes whatever register the DMA's address
--! happens to select. That's how a DMC DMA during a controller read on a real
--! NES can read `$4016` twice and lose a bit.
--!
--! Writes are blocked during Phi1, so they only happen during Phi2, when the
--! CPU drives the data bus and the APU's counters aren't moving. Reads last
--! the whole cycle.
--!
--! The debug registers (`$4018`-`$401A`) only decode while the DBG pin is
--! high. Then every read of `$4000`-`$401F` also asserts
--! @ref Ricoh_2A03_Signal_DBGRD, which stops the data pins driving the
--! internal data bus.
--!
--! The real chip outputs the read strobes and `/DBGRD` active-low. This core
--! keeps them active-high.
entity register_decoder is
    port(
        --! @ref MOS_6502_Phi1
        phi1: in std_ulogic;
        --! The CPU's address bus (`CPU_A0`-`CPU_A15`)
        cpu_address: in std_ulogic_vector(15 downto 0);
        --! The low bits of the address on the pins (`A0`-`A4`), from the
        --! @ref address_multiplexer
        pin_address: in std_ulogic_vector(4 downto 0);
        --! The CPU's @ref MOS_6502_Signal_R_NOT_W
        read_not_write_R_NOT_W: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_DBG
        debug_DBG: in std_ulogic;

        --! @ref Ricoh_2A03_Signal_W40xx "W4000": square 0 duty and envelope
        write_W4000: out std_ulogic;
        --! `W4001`: square 0 sweep
        write_W4001: out std_ulogic;
        --! `W4002`: square 0 period, low byte
        write_W4002: out std_ulogic;
        --! `W4003`: square 0 period, high bits, and length
        write_W4003: out std_ulogic;
        --! `W4004`: square 1 duty and envelope
        write_W4004: out std_ulogic;
        --! `W4005`: square 1 sweep
        write_W4005: out std_ulogic;
        --! `W4006`: square 1 period, low byte
        write_W4006: out std_ulogic;
        --! `W4007`: square 1 period, high bits, and length
        write_W4007: out std_ulogic;
        --! `W4008`: triangle linear counter
        write_W4008: out std_ulogic;
        --! `W400A`: triangle period, low byte
        write_W400A: out std_ulogic;
        --! `W400B`: triangle period, high bits, and length
        write_W400B: out std_ulogic;
        --! `W400C`: noise envelope
        write_W400C: out std_ulogic;
        --! `W400E`: noise mode and period
        write_W400E: out std_ulogic;
        --! `W400F`: noise length
        write_W400F: out std_ulogic;
        --! `W4010`: DMC rate, loop and IRQ enable
        write_W4010: out std_ulogic;
        --! `W4011`: DMC output level
        write_W4011: out std_ulogic;
        --! `W4012`: DMC sample address
        write_W4012: out std_ulogic;
        --! `W4013`: DMC sample length
        write_W4013: out std_ulogic;
        --! `W4014`: sprite DMA page
        write_W4014: out std_ulogic;
        --! `W4015`: channel enables
        write_W4015: out std_ulogic;
        --! `W4016`: output ports
        write_W4016: out std_ulogic;
        --! `W4017`: frame counter mode and IRQ inhibit
        write_W4017: out std_ulogic;
        --! `W401A`: debug lock and triangle output (DBG only)
        write_W401A: out std_ulogic;

        --! @ref Ricoh_2A03_Signal_R40xx "R4015": status
        read_R4015: out std_ulogic;
        --! `R4016`: input port 0, out through the `/IN0` pin
        read_R4016: out std_ulogic;
        --! `R4017`: input port 1, out through the `/IN1` pin
        read_R4017: out std_ulogic;
        --! `R4018`: square outputs (DBG only)
        read_R4018: out std_ulogic;
        --! `R4019`: triangle and noise outputs (DBG only)
        read_R4019: out std_ulogic;
        --! `R401A`: DMC output (DBG only)
        read_R401A: out std_ulogic;
        --! @ref Ricoh_2A03_Signal_DBGRD
        debug_read_DBGRD: out std_ulogic
    );
end entity register_decoder;

architecture rtl of register_decoder is
    --! The CPU is addressing `$4000`-`$401F`
    signal register_space: boolean;
    --! @ref Ricoh_2A03_Signal_REGRD
    signal REGRD: boolean;
    --! @ref Ricoh_2A03_Signal_REGWR
    signal REGWR: boolean;
    --! Writes are blocked during Phi1
    signal write_phase: boolean;
    signal debug: boolean;

    --! Whether `pin_address` selects register `$40xx`, where `xx` is
    --! `index`. Each PLA row matches one address.
    function selects(address: std_ulogic_vector(4 downto 0); index: natural)
        return boolean is
        variable row: std_ulogic_vector(4 downto 0);
    begin
        for i in 0 to 4 loop
            if (index / 2 ** i) mod 2 = 1 then
                row(i) := '1';
            else
                row(i) := '0';
            end if;
        end loop;
        return address = row;
    end function;

    function to_std(value: boolean) return std_ulogic is
    begin
        if value then
            return '1';
        end if;
        return '0';
    end function;
begin
    register_space <= cpu_address(15 downto 5) = "01000000000";
    REGRD <= register_space and read_not_write_R_NOT_W = '1';
    REGWR <= register_space and read_not_write_R_NOT_W = '0';
    write_phase <= phi1 = '0';
    debug <= debug_DBG = '1';

    write_W4000 <= to_std(write_phase and REGWR and selects(pin_address, 16#00#));
    write_W4001 <= to_std(write_phase and REGWR and selects(pin_address, 16#01#));
    write_W4002 <= to_std(write_phase and REGWR and selects(pin_address, 16#02#));
    write_W4003 <= to_std(write_phase and REGWR and selects(pin_address, 16#03#));
    write_W4004 <= to_std(write_phase and REGWR and selects(pin_address, 16#04#));
    write_W4005 <= to_std(write_phase and REGWR and selects(pin_address, 16#05#));
    write_W4006 <= to_std(write_phase and REGWR and selects(pin_address, 16#06#));
    write_W4007 <= to_std(write_phase and REGWR and selects(pin_address, 16#07#));
    write_W4008 <= to_std(write_phase and REGWR and selects(pin_address, 16#08#));
    write_W400A <= to_std(write_phase and REGWR and selects(pin_address, 16#0A#));
    write_W400B <= to_std(write_phase and REGWR and selects(pin_address, 16#0B#));
    write_W400C <= to_std(write_phase and REGWR and selects(pin_address, 16#0C#));
    write_W400E <= to_std(write_phase and REGWR and selects(pin_address, 16#0E#));
    write_W400F <= to_std(write_phase and REGWR and selects(pin_address, 16#0F#));
    write_W4010 <= to_std(write_phase and REGWR and selects(pin_address, 16#10#));
    write_W4011 <= to_std(write_phase and REGWR and selects(pin_address, 16#11#));
    write_W4012 <= to_std(write_phase and REGWR and selects(pin_address, 16#12#));
    write_W4013 <= to_std(write_phase and REGWR and selects(pin_address, 16#13#));
    write_W4014 <= to_std(write_phase and REGWR and selects(pin_address, 16#14#));
    write_W4015 <= to_std(write_phase and REGWR and selects(pin_address, 16#15#));
    write_W4016 <= to_std(write_phase and REGWR and selects(pin_address, 16#16#));
    write_W4017 <= to_std(write_phase and REGWR and selects(pin_address, 16#17#));
    write_W401A <= to_std(write_phase and debug and REGWR and selects(pin_address, 16#1A#));

    read_R4015 <= to_std(REGRD and selects(pin_address, 16#15#));
    read_R4016 <= to_std(REGRD and selects(pin_address, 16#16#));
    read_R4017 <= to_std(REGRD and selects(pin_address, 16#17#));
    read_R4018 <= to_std(debug and REGRD and selects(pin_address, 16#18#));
    read_R4019 <= to_std(debug and REGRD and selects(pin_address, 16#19#));
    read_R401A <= to_std(debug and REGRD and selects(pin_address, 16#1A#));
    debug_read_DBGRD <= to_std(debug and REGRD);
end architecture rtl;
