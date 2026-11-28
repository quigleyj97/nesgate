library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

--! @file
--! @brief The noise channel
--! @details Its registers are at `$400C`-`$400F`:
--!
--! | Register | Bits | Meaning                                               |
--! |----------|------|-------------------------------------------------------|
--! | `$400C`  | 5-0  | Envelope (see @ref envelope_unit)                     |
--! | `$400E`  | 7    | Mode: tap bit 6 of the random LFSR instead of bit 1   |
--! | `$400E`  | 3-0  | Period index                                          |
--! | `$400F`  | 7-3  | Length (see @ref length_counter)                      |
--!
--! **Frequency.** A PLA decodes the period index into a seed for the 11-bit
--! frequency LFSR. The LFSR steps every APU cycle, until it reaches the state
--! with only bit 0 set, and then reloads the seed. The seeds are picked so
--! that it reloads every 2, 4, 8, 16, 32, 48, 64, 80, 101, 127, 190, 254, 381,
--! 508, 1017 or 2034 APU cycles. During reset it shifts in zeros, and once
--! it's all zeros it shifts in a one, so it can never get stuck.
--!
--! **Random LFSR.** Each reload of the frequency LFSR steps the 15-bit random
--! LFSR. It shifts right, and feeds bit 0 XOR bit 1 (or bit 6, in mode 1)
--! into bit 14. It's held in static registers rather than dynamic latches,
--! since it can go thousands of cycles between steps. It also shifts in a one
--! once it's all zeros, which is how it gets going after power on. While
--! @ref Ricoh_2A03_Signal_LOCK is set it shifts in zeros instead.
--!
--! **Output.** The envelope's volume, while bit 0 of the random LFSR is clear
--! and the length counter hasn't finished (@ref Ricoh_2A03_Signal_NOxx).
--! While @ref Ricoh_2A03_Signal_LOCK is set, the volume all the time.
--!
--! The LFSRs' input nodes load during ACLK2, and their output latches copy
--! them during ACLK1. Every latch is sampled on the @ref metaclock while its
--! enable is high.
entity noise_channel is
    port(
        --! @ref Ricoh_2A03_Signal_ACLK1
        aclk1: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_ACLK2
        aclk2: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_RES
        reset_RES: in std_ulogic;
        --! The internal data bus (@ref Ricoh_2A03_DB)
        bus_DB_in: in std_ulogic_vector(7 downto 0);
        --! `W400C`, from the @ref register_decoder
        write_W400C: in std_ulogic;
        --! `W400E`, from the @ref register_decoder
        write_W400E: in std_ulogic;
        --! `W400F`, from the @ref register_decoder
        write_W400F: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_LFO1
        quarter_frame_LFO1: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_NOxx, from the channel's
        --! @ref length_counter
        silenced_NORND: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_LOCK
        debug_lock_LOCK: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_xx_LC, to the channel's
        --! @ref length_counter
        length_carry_LC: out std_ulogic;
        --! The channel's output (`RND`), for the DAC
        output_RND: out std_ulogic_vector(3 downto 0);
        --! @ref metaclock
        metaclock: in std_ulogic
    );
end entity noise_channel;

architecture rtl of noise_channel is
    component envelope_unit is
        port(
            aclk1: in std_ulogic;
            reset_RES: in std_ulogic;
            bus_DB_in: in std_ulogic_vector(7 downto 0);
            write_control: in std_ulogic;
            write_length: in std_ulogic;
            quarter_frame_LFO1: in std_ulogic;
            volume: out std_ulogic_vector(3 downto 0);
            length_carry_LC: out std_ulogic;
            metaclock: in std_ulogic
        );
    end component;
    for envelope: envelope_unit use entity work.envelope_unit;

    type seed_table is array(0 to 15) of std_ulogic_vector(10 downto 0);
    --! The decoder PLA's second stage: the frequency LFSR's seed for each
    --! period index. The comments give the period in APU cycles.
    constant SEEDS: seed_table := (
        "00000000010", --  0: 2
        "00000001010", --  1: 4
        "00010101010", --  2: 8
        "01010111011", --  3: 16
        "00100111001", --  4: 32
        "00101110011", --  5: 48
        "00001100011", --  6: 64
        "00001100111", --  7: 80
        "00110101001", --  8: 101
        "00100000110", --  9: 127
        "01000100111", -- 10: 190
        "00001100010", -- 11: 254
        "11001000010", -- 12: 381
        "01000001111", -- 13: 508
        "01100000000", -- 14: 1017
        "00101000000"  -- 15: 2034
    );

    --! `$400E` bit 7: the mode
    signal mode: std_ulogic := '0';
    --! `$400E` bits 3-0: the period index (`NF`), cleared by reset
    signal period_index: std_ulogic_vector(3 downto 0) := (others => '0');

    --! The frequency LFSR's input nodes
    signal frequency_nodes: std_ulogic_vector(10 downto 0) := (others => '0');
    --! The frequency LFSR's output latches
    signal frequency_lfsr: std_ulogic_vector(10 downto 0) := (others => '0');
    --! The frequency LFSR is all zeros (`NFZ`)
    signal frequency_zero: std_ulogic;
    --! The value shifted into bit 10 (`NSIN`)
    signal frequency_shift_in: std_ulogic;
    --! The frequency LFSR is due to reload
    signal reload_due: std_ulogic;
    --! `NFLOAD`: reload the frequency LFSR. Also `RSTEP`, which steps the
    --! random LFSR.
    signal NFLOAD: std_ulogic;
    --! `NFSTEP`: step the frequency LFSR
    signal NFSTEP: std_ulogic;

    --! The random LFSR's registers
    signal random_registers: std_ulogic_vector(14 downto 0) := (others => '0');
    --! The random LFSR's output latches
    signal random_lfsr: std_ulogic_vector(14 downto 0) := (others => '0');
    --! The value shifted into bit 14 (`RIN`)
    signal random_shift_in: std_ulogic;
    --! The second tap: bit 1, or bit 6 in mode 1
    signal tap: std_ulogic;
    --! The random LFSR is all zeros (`RSOZ`)
    signal random_zero: std_ulogic;

    signal volume: std_ulogic_vector(3 downto 0);
begin
    envelope: envelope_unit
        port map(
            aclk1 => aclk1,
            reset_RES => reset_RES,
            bus_DB_in => bus_DB_in,
            write_control => write_W400C,
            write_length => write_W400F,
            quarter_frame_LFO1 => quarter_frame_LFO1,
            volume => volume,
            length_carry_LC => length_carry_LC,
            metaclock => metaclock
        );

    frequency_zero <= '1' when frequency_lfsr = "00000000000" else '0';
    reload_due <= '1' when frequency_lfsr = "00000000001" and reset_RES = '0'
        else '0';
    NFLOAD <= aclk2 and reload_due;
    NFSTEP <= aclk2 and not reload_due;
    frequency_shift_in <= ((frequency_lfsr(0) xor frequency_lfsr(2))
        or frequency_zero) and not reset_RES;

    tap <= random_lfsr(6) when mode = '1' else random_lfsr(1);
    random_zero <= '1' when random_lfsr = "000000000000000" else '0';
    random_shift_in <= ((random_lfsr(0) xor tap) or random_zero)
        and not debug_lock_LOCK;

    process(metaclock)
    begin
        if rising_edge(metaclock) then
            if reset_RES = '1' then
                period_index <= (others => '0');
            elsif write_W400E = '1' then
                period_index <= bus_DB_in(3 downto 0);
            end if;
            if write_W400E = '1' then
                mode <= bus_DB_in(7);
            end if;

            if NFLOAD = '1' then
                frequency_nodes <= SEEDS(to_integer(unsigned(period_index)));
            elsif NFSTEP = '1' then
                frequency_nodes <= frequency_shift_in & frequency_lfsr(10 downto 1);
            end if;

            if NFLOAD = '1' then
                random_registers <= random_shift_in & random_lfsr(14 downto 1);
            end if;

            if aclk1 = '1' then
                frequency_lfsr <= frequency_nodes;
                random_lfsr <= random_registers;
            end if;
        end if;
    end process;

    output_RND <= volume
        when (random_lfsr(0) = '0' and silenced_NORND = '0') or debug_lock_LOCK = '1'
        else "0000";
end architecture rtl;
