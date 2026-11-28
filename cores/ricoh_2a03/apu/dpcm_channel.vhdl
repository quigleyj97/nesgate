library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

--! @file
--! @brief The delta modulation channel (DMC), and its sample DMA
--! @details Its registers are at `$4010`-`$4013`, and its enable is `$4015`
--! bit 4:
--!
--! | Register | Bits | Meaning                                               |
--! |----------|------|-------------------------------------------------------|
--! | `$4010`  | 7    | IRQ enable                                            |
--! | `$4010`  | 6    | Loop                                                  |
--! | `$4010`  | 3-0  | Rate index                                            |
--! | `$4011`  | 6-0  | Output level                                          |
--! | `$4012`  | 7-0  | Sample address: `$C000` + 64 × the value               |
--! | `$4013`  | 7-0  | Sample length: 16 × the value + 1 bytes                |
--!
--! **Rate.** A PLA decodes the rate index into a seed for the 9-bit frequency
--! LFSR, which steps every APU cycle until it reaches the state with only bit
--! 0 set, then reloads (`DFLOAD`). The seeds are picked so that it reloads
--! every 214, 190, 170, 160, 143, 127, 113, 107, 95, 80, 71, 64, 53, 42, 36 or
--! 27 APU cycles.
--!
--! **Output.** Each reload:
--!
--! - steps the output, a 6-bit reversible @ref apu_counter "counter" (bits
--!   6-1 of the output level), up if bit 0 of the sample shift register is
--!   set, and down if not. It stops instead of wrapping (`DOUT`), and doesn't
--!   step while the channel is silent, or while
--!   @ref Ricoh_2A03_Signal_LOCK is set. Bit 0 of the level is only ever
--!   written by `$4011`.
--! - steps the 3-bit sample bit counter.
--! - shifts the sample shift register right, unless the bit counter is at 7.
--!   Then the shift register loads the sample buffer instead, if it's full,
--!   which empties it. If it's empty the channel goes silent until the next
--!   load.
--!
--! **Sample fetches.** The address and length counters load from `$4012`
--! and `$4013` (`DSLOAD`) when the channel is enabled, and again when a
--! sample ends with loop set. Each fetch steps them (`DSSTEP`). After the
--! last byte the channel disables itself, and sets its interrupt flag, unless
--! loop is set. The address counter is 15 bits, plus `A15` tied high, so it
--! wraps from `$FFFF` to `$8000`.
--!
--! While the channel is enabled and the sample buffer is empty, the next Phi2
--! of a CPU read cycle starts a DMA (`DMAStart`), which drops
--! @ref Ricoh_2A03_Signal_DMCRDY to stall the CPU. Then:
--!
--! 1. The next ACLK2 latches the start, and the ACLK1 after it hands the
--!    address pins to the DMC (@ref Ricoh_2A03_Signal_DMCAB) and pauses the
--!    sprite DMA (@ref Ricoh_2A03_Signal_RUNDMC).
--! 2. During Phi2 of that cycle, `PCM` loads the sample buffer from the data
--!    bus, which ends the DMA.
--! 3. The next ACLK2 gives the address pins back, and the CPU carries on.
--!
--! **Interrupt.** The interrupt flag is set when a sample ends without loop.
--! It's cleared by any write to `$4015`, and while the IRQ enable is clear.
--! Reading `$4015` puts it on bit 7, and the channel's enable on bit 4. It
--! goes to the CPU as @ref Ricoh_2A03_Signal_DMCINT, through the
--! @ref frame_counter.
--!
--! The chip keeps several control flip-flops' signals in complementary form.
--! This entity keeps everything active-high. Every latch is sampled on the
--! @ref metaclock while its enable is high.
entity dpcm_channel is
    port(
        --! @ref MOS_6502_Phi1. Sample fetches happen while it's low.
        phi1: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_ACLK1
        aclk1: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_ACLK2
        aclk2: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_RES
        reset_RES: in std_ulogic;
        --! The internal data bus (@ref Ricoh_2A03_DB)
        bus_DB_in: in std_ulogic_vector(7 downto 0);
        --! The CPU's @ref MOS_6502_Signal_R_NOT_W, to find its read cycles
        read_not_write_R_NOT_W: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_LOCK
        debug_lock_LOCK: in std_ulogic;
        --! `W4010`, from the @ref register_decoder
        write_W4010: in std_ulogic;
        --! `W4011`, from the @ref register_decoder
        write_W4011: in std_ulogic;
        --! `W4012`, from the @ref register_decoder
        write_W4012: in std_ulogic;
        --! `W4013`, from the @ref register_decoder
        write_W4013: in std_ulogic;
        --! `W4015`, from the @ref register_decoder
        write_W4015: in std_ulogic;
        --! `R4015`, from the @ref register_decoder
        read_R4015: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_DMCAB
        dmc_address_bus_DMCAB: out std_ulogic;
        --! @ref Ricoh_2A03_Signal_RUNDMC
        dmc_running_RUNDMC: out std_ulogic;
        --! @ref Ricoh_2A03_Signal_DMCRDY
        dmc_ready_DMCRDY: out std_ulogic;
        --! @ref Ricoh_2A03_Signal_DMCINT
        dmc_interrupt_DMCINT: out std_ulogic;
        --! The address to fetch the next sample byte from (`DMC_A`)
        dmc_address: out std_ulogic_vector(15 downto 0);
        --! Drives @ref Ricoh_2A03_DB bits 7 and 4 while reading `$4015`, all
        --! ones (released) otherwise
        bus_DB_out: out std_ulogic_vector(7 downto 0);
        --! The channel's output level (`DMC`), for the DAC
        output_DMC: out std_ulogic_vector(6 downto 0);
        --! @ref metaclock
        metaclock: in std_ulogic
    );
end entity dpcm_channel;

architecture rtl of dpcm_channel is
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
    for address_counter: apu_counter use entity work.apu_counter;
    for length_counter: apu_counter use entity work.apu_counter;
    for bit_counter: apu_counter use entity work.apu_counter;
    for output_counter: apu_counter use entity work.apu_counter;

    type seed_table is array(0 to 15) of std_ulogic_vector(8 downto 0);
    --! The decoder PLA's second stage: the frequency LFSR's seed for each
    --! rate index. The comments give the period in APU cycles.
    constant SEEDS: seed_table := (
        "101110011", --  0: 214
        "010001010", --  1: 190
        "101000011", --  2: 170
        "011011011", --  3: 160
        "111101110", --  4: 143
        "000111111", --  5: 127
        "001111101", --  6: 113
        "111010001", --  7: 107
        "000001001", --  8: 95
        "011011100", --  9: 80
        "011110001", -- 10: 71
        "011111001", -- 11: 64
        "010001101", -- 12: 53
        "110001001", -- 13: 42
        "110001110", -- 14: 36
        "101010110"  -- 15: 27
    );

    -- #region Registers
    --! `$4010` bit 7: IRQ enable (`/IRQEN` is its inverse)
    signal irq_enabled: std_ulogic := '0';
    --! `$4010` bit 6: loop (`LOOP`)
    signal loop_sample: std_ulogic := '0';
    --! `$4010` bits 3-0: the rate index (`Fx`)
    signal rate_index: std_ulogic_vector(3 downto 0) := (others => '0');
    --! `$4011` bit 0: bit 0 of the output level
    signal output_bit_0: std_ulogic := '0';
    --! `$4012`: the sample address (`DPA`)
    signal address_register: std_ulogic_vector(7 downto 0) := (others => '0');
    --! `$4013`: the sample length (`DSC`)
    signal length_register: std_ulogic_vector(7 downto 0) := (others => '0');
    -- #endregion

    -- #region Interrupt and enable control
    --! The interrupt flag
    signal interrupt_flag: std_ulogic := '0';
    --! `$4015` bit 4: the channel is enabled (`ED2`). Cleared when a sample
    --! ends without loop.
    signal enabled: std_ulogic := '0';
    --! The enable, latched during ACLK1, then ACLK2, then ACLK1 again
    signal enabled_latch1: std_ulogic := '0';
    signal enabled_latch2: std_ulogic := '0';
    signal enabled_latch3: std_ulogic := '0';
    --! `ED1`: a sample has ended without loop
    signal ED1: std_ulogic;
    --! `DMC3`: the channel has just been enabled
    signal DMC3: std_ulogic;
    -- #endregion

    -- #region DMA control
    --! `DMAStart`: a DMA has been requested
    signal DMAStart: std_ulogic := '0';
    --! `DMAStart`, latched during ACLK2
    signal start_latch: std_ulogic := '0';
    --! `RUNDMC`: `DMAStart`, latched during ACLK2 then ACLK1
    signal RUNDMC: std_ulogic := '0';
    --! The DMC owns the address pins (the inverse of `/DMCAB`)
    signal DMCAB: std_ulogic := '0';
    -- #endregion

    -- #region Sample buffer control
    --! `PCM`: load the sample buffer from the data bus
    signal PCM: std_ulogic;
    --! The sample buffer is full
    signal buffer_full: std_ulogic := '0';
    --! `buffer_full`, latched during ACLK1
    signal buffer_full_latch: std_ulogic := '0';
    --! A byte has been fetched since the last ACLK2
    signal fetched: std_ulogic := '0';
    --! `fetched`, latched during ACLK1
    signal fetched_latch: std_ulogic := '0';
    --! `DMC1` (`PCMDone`): the ACLK2 after a fetch
    signal PCMDone: std_ulogic;
    --! The shift register holds a sample byte (the channel isn't silent)
    signal playing: std_ulogic := '0';
    --! `playing`, latched during ACLK1
    signal playing_latch: std_ulogic := '0';
    --! `BLOAD`: load the shift register from the sample buffer
    signal BLOAD: std_ulogic;
    --! `BSTEP`: shift the shift register
    signal BSTEP: std_ulogic;
    --! `DSTEP`: step the output counter
    signal DSTEP: std_ulogic;
    --! `DSLOAD`: load the address and length counters
    signal DSLOAD: std_ulogic;
    --! `DSSTEP`: step the address and length counters
    signal DSSTEP: std_ulogic;
    -- #endregion

    -- #region Rate
    --! The frequency LFSR's input nodes
    signal frequency_nodes: std_ulogic_vector(8 downto 0) := (others => '0');
    --! The frequency LFSR's output latches
    signal frequency_lfsr: std_ulogic_vector(8 downto 0) := (others => '0');
    --! The value shifted into bit 8
    signal frequency_shift_in: std_ulogic;
    signal frequency_zero: std_ulogic;
    --! The frequency LFSR is due to reload
    signal reload_due: std_ulogic;
    --! `DFLOAD`: reload the frequency LFSR
    signal DFLOAD: std_ulogic;
    --! `DFSTEP`: step the frequency LFSR
    signal DFSTEP: std_ulogic;
    -- #endregion

    -- #region Sample data
    --! The sample buffer
    signal sample_buffer: std_ulogic_vector(7 downto 0) := (others => '0');
    --! The sample shift register's nodes
    signal shift_register: std_ulogic_vector(7 downto 0) := (others => '1');
    --! The shift register shifted right, latched during ACLK1
    signal shifted_latch: std_ulogic_vector(7 downto 0) := (others => '1');
    --! The sample bit counter is at 7, latched during ACLK1 (`NOUT`)
    signal NOUT: std_ulogic := '0';
    signal bit_counter_done: std_ulogic;
    --! The length counter has finished (`SOUT`)
    signal SOUT: std_ulogic;
    --! `SOUT`, latched during ACLK1 (`DMC2`)
    signal SOUT_latch: std_ulogic := '0';
    --! The output counter has stopped (`DOUT`)
    signal DOUT: std_ulogic;
    --! `DOUT`, latched during ACLK1
    signal DOUT_latch: std_ulogic := '0';
    --! Count the output down (`/BOUT`): bit 0 of the shift register is clear
    signal count_down: std_ulogic;
    signal address_start: std_ulogic_vector(14 downto 0);
    signal address_count: std_ulogic_vector(14 downto 0);
    signal length_start: std_ulogic_vector(11 downto 0);
    signal output_level: std_ulogic_vector(5 downto 0);
    -- #endregion
begin
    -- #region Counters
    address_start <= '1' & address_register & "000000";
    address_counter: apu_counter
        generic map(width => 15)
        port map(
            clock => aclk1,
            load => DSLOAD,
            clear => reset_RES,
            step => DSSTEP,
            carry_in => '1',
            count_down => '0',
            value_in => address_start,
            value_out => address_count,
            carry_out => open,
            metaclock => metaclock
        );

    length_start <= length_register & "0000";
    length_counter: apu_counter
        generic map(width => 12)
        port map(
            clock => aclk1,
            load => DSLOAD,
            clear => reset_RES,
            step => DSSTEP,
            carry_in => '1',
            count_down => '1',
            value_in => length_start,
            value_out => open,
            carry_out => SOUT,
            metaclock => metaclock
        );

    bit_counter: apu_counter
        generic map(width => 3)
        port map(
            clock => aclk1,
            load => reset_RES,
            clear => reset_RES,
            step => DFLOAD,
            carry_in => '1',
            count_down => '0',
            value_in => "000",
            value_out => open,
            carry_out => bit_counter_done,
            metaclock => metaclock
        );

    output_counter: apu_counter
        generic map(width => 6)
        port map(
            clock => aclk1,
            load => write_W4011,
            clear => reset_RES,
            step => DSTEP,
            carry_in => '1',
            count_down => count_down,
            value_in => bus_DB_in(6 downto 1),
            value_out => output_level,
            carry_out => DOUT,
            metaclock => metaclock
        );
    -- #endregion

    -- Rate
    frequency_zero <= '1' when frequency_lfsr = "000000000" else '0';
    reload_due <= '1' when frequency_lfsr = "000000001" and reset_RES = '0'
        else '0';
    DFLOAD <= aclk2 and reload_due;
    DFSTEP <= aclk2 and not reload_due;
    frequency_shift_in <= ((frequency_lfsr(0) xor frequency_lfsr(4))
        or frequency_zero) and not reset_RES;

    -- Enable and sample counter control
    ED1 <= not loop_sample and SOUT_latch and PCMDone;
    DMC3 <= aclk2 and enabled_latch1 and not enabled_latch3;
    DSLOAD <= (SOUT_latch and PCMDone) or DMC3;
    DSSTEP <= PCMDone and not DMC3 and not SOUT_latch;

    -- Sample buffer control
    PCM <= not phi1 and DMCAB;
    PCMDone <= aclk2 and fetched_latch;
    DSTEP <= DFLOAD and not DOUT_latch and playing_latch and not debug_lock_LOCK;
    BLOAD <= DFLOAD and NOUT and buffer_full_latch;
    BSTEP <= DFLOAD and not NOUT;
    count_down <= not shift_register(0);

    process(metaclock)
    begin
        if rising_edge(metaclock) then
            -- Registers
            if write_W4010 = '1' then
                irq_enabled <= bus_DB_in(7);
                loop_sample <= bus_DB_in(6);
                rate_index <= bus_DB_in(3 downto 0);
            end if;
            if write_W4011 = '1' then
                output_bit_0 <= bus_DB_in(0);
            end if;
            if write_W4012 = '1' then
                address_register <= bus_DB_in;
            end if;
            if write_W4013 = '1' then
                length_register <= bus_DB_in;
            end if;

            -- Interrupt and enable
            if write_W4015 = '1' or irq_enabled = '0' or reset_RES = '1' then
                interrupt_flag <= '0';
            elsif ED1 = '1' then
                interrupt_flag <= '1';
            end if;
            if ED1 = '1' or reset_RES = '1' then
                enabled <= '0';
            elsif write_W4015 = '1' then
                enabled <= bus_DB_in(4);
            end if;

            -- DMA control
            if enabled_latch3 = '0' or reset_RES = '1' or buffer_full = '1' then
                DMAStart <= '0';
            elsif phi1 = '0' and read_not_write_R_NOT_W = '1' then
                DMAStart <= '1';
            end if;
            if aclk2 = '1' then
                DMCAB <= '0';
            elsif aclk1 = '1' and start_latch = '1' then
                DMCAB <= '1';
            end if;

            -- Sample buffer control
            if BLOAD = '1' or reset_RES = '1' then
                buffer_full <= '0';
            elsif PCM = '1' then
                buffer_full <= '1';
            end if;
            if PCMDone = '1' or reset_RES = '1' then
                fetched <= '0';
            elsif PCM = '1' then
                fetched <= '1';
            end if;
            if (DFLOAD = '1' and NOUT = '1' and buffer_full_latch = '0')
                or reset_RES = '1' then
                playing <= '0';
            elsif BLOAD = '1' then
                playing <= '1';
            end if;

            if PCM = '1' then
                sample_buffer <= bus_DB_in;
            end if;
            if reset_RES = '1' then
                shift_register <= (others => '1');
            elsif BLOAD = '1' then
                shift_register <= sample_buffer;
            elsif BSTEP = '1' then
                shift_register <= shifted_latch;
            end if;

            -- Rate
            if DFLOAD = '1' then
                frequency_nodes <= SEEDS(to_integer(unsigned(rate_index)));
            elsif DFSTEP = '1' then
                frequency_nodes <= frequency_shift_in & frequency_lfsr(8 downto 1);
            end if;

            if aclk1 = '1' then
                enabled_latch1 <= enabled;
                enabled_latch3 <= enabled_latch2;
                RUNDMC <= start_latch;
                buffer_full_latch <= buffer_full;
                fetched_latch <= fetched;
                playing_latch <= playing;
                shifted_latch <= '0' & shift_register(7 downto 1);
                NOUT <= bit_counter_done;
                SOUT_latch <= SOUT;
                DOUT_latch <= DOUT;
                frequency_lfsr <= frequency_nodes;
            end if;
            if aclk2 = '1' then
                enabled_latch2 <= enabled_latch1;
                start_latch <= DMAStart;
            end if;
        end if;
    end process;

    dmc_address_bus_DMCAB <= DMCAB;
    dmc_running_RUNDMC <= RUNDMC;
    dmc_ready_DMCRDY <= not DMAStart and not DMCAB;
    dmc_interrupt_DMCINT <= interrupt_flag and irq_enabled;
    dmc_address <= '1' & address_count;
    bus_DB_out <= (7 => interrupt_flag, 4 => enabled, others => '1')
        when read_R4015 = '1' else (others => '1');
    output_DMC <= output_level & output_bit_0;
end architecture rtl;
