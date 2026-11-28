library ieee;
use ieee.std_logic_1164.all;

--! @file
--! @brief The triangle channel
--! @details Its registers are at `$4008`-`$400B`:
--!
--! | Register | Bits | Meaning                                               |
--! |----------|------|-------------------------------------------------------|
--! | `$4008`  | 7    | Control: keep reloading the linear counter, and halt the length counter |
--! | `$4008`  | 6-0  | Linear counter reload value                           |
--! | `$400A`  | 7-0  | Period, low byte                                      |
--! | `$400B`  | 7-3  | Length (see @ref length_counter)                      |
--! | `$400B`  | 2-0  | Period, high bits                                     |
--!
--! **Frequency.** Unlike the other channels, the triangle's frequency and
--! output counters run on Phi1 and Phi2 instead of ACLK, so they step every
--! CPU cycle. That halves the size of the output's steps for a given pitch.
--! The 11-bit period loads an 11-bit @ref apu_counter "down counter", which
--! steps during Phi2 and reloads when it reaches zero (`FOUT`, latched during
--! Phi1), so it reloads every period + 1 CPU cycles.
--!
--! **Output.** Each reload steps a 5-bit up counter (`TTSTEP`), unless the
--! linear counter or the length counter (@ref Ricoh_2A03_Signal_NOxx) is at
--! zero, or @ref Ricoh_2A03_Signal_LOCK is set. The output is its low four
--! bits, inverted while bit 4 is clear, so it runs 15 down to 0, then 0 up
--! to 15. The counter only stops, so the output holds its level when the
--! channel is silenced. In debug mode a write to `$401A` loads the counter
--! from bits 4-0.
--!
--! **Linear counter.** A 7-bit down counter, clocked by the quarter frame
--! (@ref Ricoh_2A03_Signal_LFO1). A write to `$400B` sets the reload flag,
--! and while it's set each quarter frame reloads the counter from `$4008`.
--! Otherwise each quarter frame steps it until it reaches zero. The quarter
--! frame clears the flag, unless the control bit is set.
--!
--! The control bit also goes to the channel's @ref length_counter,
--! inverted, as @ref Ricoh_2A03_Signal_xx_LC.
--!
--! The real chip latches the reload flip-flop twice during ACLK1, once each
--! way round, and this entity keeps one latch for both. Every latch is
--! sampled on the @ref metaclock while its enable is high.
entity triangle_channel is
    port(
        --! @ref MOS_6502_Phi1. The frequency and output counters step while low
        phi1: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_ACLK1
        aclk1: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_RES
        reset_RES: in std_ulogic;
        --! The internal data bus (@ref Ricoh_2A03_DB)
        bus_DB_in: in std_ulogic_vector(7 downto 0);
        --! `W4008`, from the @ref register_decoder
        write_W4008: in std_ulogic;
        --! `W400A`, from the @ref register_decoder
        write_W400A: in std_ulogic;
        --! `W400B`, from the @ref register_decoder
        write_W400B: in std_ulogic;
        --! `W401A`, from the @ref register_decoder (debug mode only)
        write_W401A: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_LFO1
        quarter_frame_LFO1: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_NOxx, from the channel's
        --! @ref length_counter
        silenced_NOTRI: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_LOCK
        debug_lock_LOCK: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_xx_LC, to the channel's
        --! @ref length_counter
        length_carry_LC: out std_ulogic;
        --! The channel's output (`TRI`), for the DAC
        output_TRI: out std_ulogic_vector(3 downto 0);
        --! @ref metaclock
        metaclock: in std_ulogic
    );
end entity triangle_channel;

architecture rtl of triangle_channel is
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
    for linear_counter: apu_counter use entity work.apu_counter;
    for frequency_counter: apu_counter use entity work.apu_counter;
    for output_counter: apu_counter use entity work.apu_counter;

    --! `$4008` bit 7: the control bit
    signal control: std_ulogic := '0';
    --! `$4008` bits 6-0: the linear counter's reload value
    signal linear_register: std_ulogic_vector(6 downto 0) := (others => '0');
    --! `$400A` and `$400B` bits 2-0: the period
    signal period_register: std_ulogic_vector(10 downto 0) := (others => '0');

    --! The linear counter reload flag (`TRELOAD`)
    signal reload_flag: std_ulogic := '0';
    --! The reload flag, latched during ACLK1
    signal reload_latch: std_ulogic := '0';
    --! The linear counter is at zero (`TCO`)
    signal TCO: std_ulogic;
    --! `TCO`, latched during ACLK1
    signal linear_done_latch: std_ulogic := '0';
    --! `TLOAD`: reload the linear counter
    signal TLOAD: std_ulogic;
    --! `TSTEP`: step the linear counter
    signal TSTEP: std_ulogic;

    --! The frequency counter's carry out (`FOUT`)
    signal FOUT: std_ulogic;
    --! `FOUT`, latched during Phi1
    signal frequency_done_latch: std_ulogic := '0';
    --! `TFLOAD`: reload the frequency counter
    signal TFLOAD: std_ulogic;
    --! `TFSTEP`: step the frequency counter
    signal TFSTEP: std_ulogic;
    --! `TTSTEP`: step the output counter
    signal TTSTEP: std_ulogic;
    --! The output counter (`T`)
    signal T: std_ulogic_vector(4 downto 0);
begin
    linear_counter: apu_counter
        generic map(width => 7)
        port map(
            clock => aclk1,
            load => TLOAD,
            clear => reset_RES,
            step => TSTEP,
            carry_in => '1',
            count_down => '1',
            value_in => linear_register,
            value_out => open,
            carry_out => TCO,
            metaclock => metaclock
        );

    frequency_counter: apu_counter
        generic map(width => 11)
        port map(
            clock => phi1,
            load => TFLOAD,
            clear => reset_RES,
            step => TFSTEP,
            carry_in => '1',
            count_down => '1',
            value_in => period_register,
            value_out => open,
            carry_out => FOUT,
            metaclock => metaclock
        );

    output_counter: apu_counter
        generic map(width => 5)
        port map(
            clock => phi1,
            load => write_W401A,
            clear => reset_RES,
            step => TTSTEP,
            carry_in => '1',
            count_down => '0',
            value_in => bus_DB_in(4 downto 0),
            value_out => T,
            carry_out => open,
            metaclock => metaclock
        );

    TLOAD <= quarter_frame_LFO1 and reload_latch;
    TSTEP <= quarter_frame_LFO1 and not reload_latch and not linear_done_latch;
    TFLOAD <= not phi1 and frequency_done_latch;
    TFSTEP <= not phi1 and not frequency_done_latch;
    TTSTEP <= not phi1 and frequency_done_latch and not TCO
        and not silenced_NOTRI and not debug_lock_LOCK;

    process(metaclock)
    begin
        if rising_edge(metaclock) then
            if write_W4008 = '1' then
                control <= bus_DB_in(7);
                linear_register <= bus_DB_in(6 downto 0);
            end if;
            if write_W400A = '1' then
                period_register(7 downto 0) <= bus_DB_in;
            end if;
            if write_W400B = '1' then
                period_register(10 downto 8) <= bus_DB_in(2 downto 0);
            end if;

            if quarter_frame_LFO1 = '1' and reload_latch = '1' and control = '0' then
                reload_flag <= '0';
            elsif write_W400B = '1' then
                reload_flag <= '1';
            end if;

            if aclk1 = '1' then
                reload_latch <= reload_flag;
                linear_done_latch <= TCO;
            end if;
            if phi1 = '1' then
                frequency_done_latch <= FOUT;
            end if;
        end if;
    end process;

    length_carry_LC <= not control;
    output_TRI <= T(3 downto 0) when T(4) = '1' else not T(3 downto 0);
end architecture rtl;
