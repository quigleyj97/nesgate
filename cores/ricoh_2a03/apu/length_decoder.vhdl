library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

--! @file
--! @brief The length decoder, which turns the 5-bit length index written to
--! `$4003`, `$4007`, `$400B` and `$400F` into a length counter value
--! @details A two-stage PLA, shared by the four
--! @ref length_counter "length counters". The first stage decodes bits 7-3 of
--! the data bus into one of 32 lines, and the second ORs each line into the
--! bits of its value. The table below lists the value for each index.
--!
--! Each value is one less than the length it stands for, because a length
--! counter silences its channel on the step after it reaches zero, not the
--! step that reaches it. So bit 0 of every value is set, since every length is
--! even.
--!
--! The decoder reads the bus all the time. The length counters only load its
--! output during a write to their channel's register.
entity length_decoder is
    port(
        --! The internal data bus (@ref Ricoh_2A03_DB). Bits 7-3 are the index.
        bus_DB_in: in std_ulogic_vector(7 downto 0);
        --! The value to load into a length counter
        length_value: out std_ulogic_vector(7 downto 0)
    );
end entity length_decoder;

architecture rtl of length_decoder is
    type length_table is array(0 to 31) of std_ulogic_vector(7 downto 0);
    --! The second stage of the PLA, one entry per first-stage line. The
    --! comments give the length, in half frames.
    constant LENGTHS: length_table := (
        x"09", --  0: 10
        x"FD", --  1: 254
        x"13", --  2: 20
        x"01", --  3: 2
        x"27", --  4: 40
        x"03", --  5: 4
        x"4F", --  6: 80
        x"05", --  7: 6
        x"9F", --  8: 160
        x"07", --  9: 8
        x"3B", -- 10: 60
        x"09", -- 11: 10
        x"0D", -- 12: 14
        x"0B", -- 13: 12
        x"19", -- 14: 26
        x"0D", -- 15: 14
        x"0B", -- 16: 12
        x"0F", -- 17: 16
        x"17", -- 18: 24
        x"11", -- 19: 18
        x"2F", -- 20: 48
        x"13", -- 21: 20
        x"5F", -- 22: 96
        x"15", -- 23: 22
        x"BF", -- 24: 192
        x"17", -- 25: 24
        x"47", -- 26: 72
        x"19", -- 27: 26
        x"0F", -- 28: 16
        x"1B", -- 29: 28
        x"1F", -- 30: 32
        x"1D"  -- 31: 30
    );
begin
    length_value <= LENGTHS(to_integer(unsigned(bus_DB_in(7 downto 3))));
end architecture rtl;
