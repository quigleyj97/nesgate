library ieee;
use ieee.std_logic_1164.all;

--! @file
--! @brief The counter the APU builds its timers, dividers and sequencers from
--! @details Almost every counter in the APU is a chain of the same bit cell,
--! in one of three flavours: up, down, or reversible (up or down, chosen by a
--! control input). They only differ in the carry gate, so this entity models
--! the reversible cell and takes the direction as an input, which the up and
--! down counters tie off.
--!
--! Each bit has two latches:
--!
--! - The value latch, a dynamic node fed by pass MOSFETs. `load` puts
--!   `value_in` on it, `clear` grounds it, and `step` copies the carry latch
--!   into it. Otherwise it's refreshed from itself, which on FPGA fabric just
--!   means it holds. `load` beats `clear`, which beats `step`.
--! - The carry latch, which opens while `clock` is high (ACLK1 for most
--!   counters, Phi1 for the triangle channel's). It stores the bit's next
--!   value: toggled if the carry into the bit is set, otherwise unchanged.
--!
--! So the counter works out its next value while `clock` is high, and moves
--! to it when `step` is asserted. The control logic only ever steps during the
--! other phase, so the two latches are never open at once. A step uses
--! whatever the carry latches held at the last `clock`, even if the counter
--! was loaded since. The real chip does the same.
--!
--! The carry into bit 0 is `carry_in`, usually tied high. The carry out of
--! each bit is the carry into it, and the bit set (counting up) or clear
--! (counting down). The carry out of the top bit, `carry_out`, is set when the
--! next step would wrap around: when the counter is all ones counting up, or
--! all zeros counting down. The control logic uses it to reload the counter,
--! or to stop it.
--!
--! Both latches are sampled on the @ref metaclock while their enable is high,
--! like the rest of the 2A03's latches.
entity apu_counter is
    generic(
        --! The number of bits
        width: positive := 8
    );
    port(
        --! Opens the carry latches: @ref Ricoh_2A03_Signal_ACLK1, or
        --! @ref MOS_6502_Phi1 for the triangle channel's counters
        clock: in std_ulogic;
        --! Load `value_in`
        load: in std_ulogic;
        --! Clear to zero
        clear: in std_ulogic;
        --! Move to the value the carry latches hold
        step: in std_ulogic;
        --! The carry into bit 0. When low, a step leaves the counter as it is.
        carry_in: in std_ulogic;
        --! `1` to count down, `0` to count up
        count_down: in std_ulogic;
        --! The value to load
        value_in: in std_ulogic_vector(width - 1 downto 0);
        --! The counter's value
        value_out: out std_ulogic_vector(width - 1 downto 0);
        --! The carry out of the top bit: the next step wraps around
        carry_out: out std_ulogic;
        --! @ref metaclock
        metaclock: in std_ulogic
    );
end entity apu_counter;

architecture rtl of apu_counter is
    --! The value latches
    signal value: std_ulogic_vector(width - 1 downto 0) := (others => '0');
    --! The carry latches: each bit's value after the next step
    signal stepped: std_ulogic_vector(width - 1 downto 0) := (others => '0');
    --! `carries(i)` is the carry into bit `i`
    signal carries: std_ulogic_vector(width downto 0);
begin
    carry_chain: process(value, carry_in, count_down)
        variable carry: std_ulogic;
    begin
        carry := carry_in;
        for i in 0 to width - 1 loop
            carries(i) <= carry;
            carry := carry and (value(i) xor count_down);
        end loop;
        carries(width) <= carry;
    end process;

    process(metaclock)
    begin
        if rising_edge(metaclock) then
            if clock = '1' then
                stepped <= value xor carries(width - 1 downto 0);
            end if;

            if load = '1' then
                value <= value_in;
            elsif clear = '1' then
                value <= (others => '0');
            elsif step = '1' then
                value <= stepped;
            end if;
        end if;
    end process;

    value_out <= value;
    carry_out <= carries(width);
end architecture rtl;
