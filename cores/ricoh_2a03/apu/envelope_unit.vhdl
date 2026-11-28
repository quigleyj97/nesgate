library ieee;
use ieee.std_logic_1164.all;

--! @file
--! @brief The envelope unit, which sets the volume of a square or noise
--! channel
--! @details Shared by both square channels and the noise channel. It holds the
--! channel's control register (`$4000`, `$4004` or `$400C`):
--!
--! | Bits | Meaning                                                          |
--! |------|------------------------------------------------------------------|
--! | 5    | Loop the envelope, and halt the length counter                    |
--! | 4    | Constant volume: output bits 3-0 instead of the envelope          |
--! | 3-0  | The volume, or the envelope's decay period                       |
--!
--! It's two 4-bit @ref apu_counter "down counters", clocked by the quarter
--! frame (@ref Ricoh_2A03_Signal_LFO1):
--!
--! - The decay counter divides the quarter frame. It reloads from bits 3-0
--!   when it reaches zero, and otherwise counts down.
--! - The envelope counter is the volume. Each time the decay counter
--!   reloads, it counts down, or once it reaches zero, loads 15 if bit 5
--!   loops the envelope, and 0 (stays) if not.
--!
--! Writing the channel's length register (`$4003`, `$4007` or `$400F`) sets
--! the reload flag. The next quarter frame then reloads the decay counter,
--! loads 15 into the envelope counter, and clears the flag.
--!
--! Bit 5 also goes to the channel's @ref length_counter, inverted, as the
--! carry into it (@ref Ricoh_2A03_Signal_xx_LC).
--!
--! The real chip latches the reload flip-flop twice during ACLK1, once each
--! way round, and this entity keeps one latch for both. The latches open
--! during ACLK1, so a quarter frame acts on the state from the ACLK1 before
--! it. Every latch is sampled on the @ref metaclock while its enable is high.
entity envelope_unit is
    port(
        --! @ref Ricoh_2A03_Signal_ACLK1
        aclk1: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_RES
        reset_RES: in std_ulogic;
        --! The internal data bus (@ref Ricoh_2A03_DB)
        bus_DB_in: in std_ulogic_vector(7 downto 0);
        --! The channel's control register write (`W4000`, `W4004` or `W400C`)
        write_control: in std_ulogic;
        --! The channel's length register write (`W4003`, `W4007` or `W400F`)
        write_length: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_LFO1
        quarter_frame_LFO1: in std_ulogic;
        --! The channel's volume
        volume: out std_ulogic_vector(3 downto 0);
        --! @ref Ricoh_2A03_Signal_xx_LC: bit 5, inverted
        length_carry_LC: out std_ulogic;
        --! @ref metaclock
        metaclock: in std_ulogic
    );
end entity envelope_unit;

architecture rtl of envelope_unit is
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
    for decay_counter: apu_counter use entity work.apu_counter;
    for envelope_counter: apu_counter use entity work.apu_counter;

    --! Bit 4: constant volume (`ENVDIS`)
    signal constant_volume: std_ulogic := '0';
    --! Bit 5: loop the envelope, and halt the length counter
    signal loop_envelope: std_ulogic := '0';
    --! Bits 3-0: the volume, or the decay period (`VOL`)
    signal volume_register: std_ulogic_vector(3 downto 0) := (others => '0');

    --! The reload flag (`RELOAD`): set by a write to the length register,
    --! cleared by the quarter frame after it
    signal reload_flag: std_ulogic := '0';
    --! The reload flag, latched during ACLK1
    signal reload_latch: std_ulogic := '0';
    --! The decay counter isn't at zero, and the flag is clear, latched during
    --! ACLK1
    signal decay_latch: std_ulogic := '0';
    --! The envelope counter is at zero, and the flag is clear, latched during
    --! ACLK1
    signal envelope_done_latch: std_ulogic := '0';

    --! The decay counter is at zero (`RCO`)
    signal decay_done: std_ulogic;
    --! The envelope counter is at zero (`ECO`)
    signal envelope_done: std_ulogic;
    --! `RLOAD`: reload the decay counter. The envelope counter acts at the
    --! same time.
    signal decay_load: std_ulogic;
    --! `RSTEP`: step the decay counter
    signal decay_step: std_ulogic;
    --! `ESTEP`: step the envelope counter
    signal envelope_step: std_ulogic;
    --! `ERES`: load the envelope counter
    signal envelope_load: std_ulogic;
    --! `EIN`: the value the envelope counter loads, in every bit
    signal envelope_in: std_ulogic;
    --! `EIN` in every bit
    signal envelope_fill: std_ulogic_vector(3 downto 0);
    signal envelope_value: std_ulogic_vector(3 downto 0);
begin
    envelope_fill <= (others => envelope_in);

    decay_counter: apu_counter
        generic map(width => 4)
        port map(
            clock => aclk1,
            load => decay_load,
            clear => reset_RES,
            step => decay_step,
            carry_in => '1',
            count_down => '1',
            value_in => volume_register,
            value_out => open,
            carry_out => decay_done,
            metaclock => metaclock
        );

    envelope_counter: apu_counter
        generic map(width => 4)
        port map(
            clock => aclk1,
            load => envelope_load,
            clear => reset_RES,
            step => envelope_step,
            carry_in => '1',
            count_down => '1',
            value_in => envelope_fill,
            value_out => envelope_value,
            carry_out => envelope_done,
            metaclock => metaclock
        );

    decay_load <= quarter_frame_LFO1 and not decay_latch;
    decay_step <= quarter_frame_LFO1 and decay_latch;
    envelope_in <= not (envelope_done_latch and not loop_envelope);
    envelope_step <= decay_load and not envelope_done_latch and not reload_latch;
    envelope_load <= decay_load and (envelope_done_latch or reload_latch);

    process(metaclock)
    begin
        if rising_edge(metaclock) then
            if write_control = '1' then
                loop_envelope <= bus_DB_in(5);
                constant_volume <= bus_DB_in(4);
                volume_register <= bus_DB_in(3 downto 0);
            end if;

            if write_length = '1' then
                reload_flag <= '1';
            elsif quarter_frame_LFO1 = '1' and reload_latch = '1' then
                reload_flag <= '0';
            end if;

            if aclk1 = '1' then
                reload_latch <= reload_flag;
                decay_latch <= not (decay_done or reload_flag);
                envelope_done_latch <= envelope_done and not reload_flag;
            end if;
        end if;
    end process;

    volume <= volume_register when constant_volume = '1' else envelope_value;
    length_carry_LC <= not loop_envelope;
end architecture rtl;
