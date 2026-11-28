library ieee;
use ieee.std_logic_1164.all;

--! @file
--! @brief A channel's length counter, which silences it after a set number of
--! half frames
--! @details Each of the square, triangle and noise channels has one. It's an
--! 8-bit @ref apu_counter "down counter" and a status flip-flop:
--!
--! - Writing the channel's length register (`$4003`, `$4007`, `$400B` or
--!   `$400F`) loads the counter from the @ref length_decoder and sets the
--!   status flip-flop.
--! - While the flip-flop is set, every half frame
--!   (@ref Ricoh_2A03_Signal_LFO2) steps the counter down. The step after it
--!   reaches zero clears the flip-flop.
--! - The channel's enable bit in `$4015` is a register here. While it's clear,
--!   every ACLK2 clears the flip-flop, so a write to the length register only
--!   sets it until the next ACLK2.
--! - The channel holds the carry into the counter low while its halt bit
--!   (`$4000`, `$4004`, `$400C` bit 5, or `$4008` bit 7) is set, so the
--!   counter stops where it is. That's @ref Ricoh_2A03_Signal_xx_LC.
--!
--! While the flip-flop is clear, @ref Ricoh_2A03_Signal_NOxx silences the
--! channel. Reading `$4015` puts the flip-flop on the channel's bit of the
--! data bus.
--!
--! The enable, carry and step latches open during ACLK1, so the control logic
--! acts on the state from the last ACLK1. Every latch is sampled on the
--! @ref metaclock while its enable is high.
entity length_counter is
    generic(
        --! The channel's bit in `$4015`: 0 for square 0, 1 for square 1, 2
        --! for the triangle and 3 for noise
        status_bit: natural range 0 to 7 := 0
    );
    port(
        --! @ref Ricoh_2A03_Signal_ACLK1
        aclk1: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_ACLK2
        aclk2: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_RES
        reset_RES: in std_ulogic;
        --! The internal data bus (@ref Ricoh_2A03_DB)
        bus_DB_in: in std_ulogic_vector(7 downto 0);
        --! The channel's length register write (`W4003`, `W4007`, `W400B` or
        --! `W400F`)
        write_length: in std_ulogic;
        --! `W4015`, from the register decoder
        write_W4015: in std_ulogic;
        --! `R4015`, from the register decoder
        read_R4015: in std_ulogic;
        --! The value to load, from the @ref length_decoder
        length_value: in std_ulogic_vector(7 downto 0);
        --! @ref Ricoh_2A03_Signal_LFO2
        half_frame_LFO2: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_xx_LC: the counter counts (the channel's
        --! halt bit is clear)
        length_carry_LC: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_NOxx: the counter has finished, or the
        --! channel is disabled
        silenced_NO: out std_ulogic;
        --! Drives the channel's bit of @ref Ricoh_2A03_DB while reading
        --! `$4015`, all ones (released) otherwise
        bus_DB_out: out std_ulogic_vector(7 downto 0);
        --! @ref metaclock
        metaclock: in std_ulogic
    );
end entity length_counter;

architecture rtl of length_counter is
    component apu_counter is
        generic(
            width: positive := 8
        );
        port(
            clock: in std_ulogic;
            load: in std_ulogic;
            clear: in std_ulogic;
            step: in std_ulogic;
            carry_in: in std_ulogic;
            count_down: in std_ulogic;
            value_in: in std_ulogic_vector(width - 1 downto 0);
            value_out: out std_ulogic_vector(width - 1 downto 0);
            carry_out: out std_ulogic;
            metaclock: in std_ulogic
        );
    end component;
    for counter: apu_counter use entity work.apu_counter;

    --! The channel's enable bit in `$4015`
    signal enabled: std_ulogic := '0';
    --! The enable bit, inverted and latched during ACLK1
    signal disabled_latch: std_ulogic := '1';
    --! The counter's carry out, latched during ACLK1
    signal carry_latch: std_ulogic := '0';
    --! The status flip-flop: the counter is counting
    signal counting: std_ulogic := '0';
    --! The status flip-flop, latched during ACLK1
    signal counting_latch: std_ulogic := '0';
    --! Step the counter
    signal step: std_ulogic;
    signal carry_out: std_ulogic;
begin
    counter: apu_counter
        generic map(width => 8)
        port map(
            clock => aclk1,
            load => write_length,
            clear => reset_RES,
            step => step,
            carry_in => length_carry_LC,
            count_down => '1',
            value_in => length_value,
            value_out => open,
            carry_out => carry_out,
            metaclock => metaclock
        );

    step <= half_frame_LFO2 and counting_latch;

    process(metaclock)
    begin
        if rising_edge(metaclock) then
            if reset_RES = '1' then
                enabled <= '0';
            elsif write_W4015 = '1' then
                enabled <= bus_DB_in(status_bit);
            end if;

            if reset_RES = '1' or (disabled_latch = '1' and aclk2 = '1')
                or (carry_latch = '1' and step = '1') then
                counting <= '0';
            elsif write_length = '1' then
                counting <= '1';
            end if;

            if aclk1 = '1' then
                disabled_latch <= not enabled;
                carry_latch <= carry_out;
                counting_latch <= counting;
            end if;
        end if;
    end process;

    silenced_NO <= not counting;
    status: process(counting, read_R4015)
    begin
        bus_DB_out <= (others => '1');
        if read_R4015 = '1' then
            bus_DB_out(status_bit) <= counting;
        end if;
    end process;
end architecture rtl;
