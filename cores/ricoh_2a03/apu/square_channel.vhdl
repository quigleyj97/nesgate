library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

--! @file
--! @brief A square (pulse) channel
--! @details The 2A03 has two, at `$4000`-`$4003` and `$4004`-`$4007`:
--!
--! | Register | Bits | Meaning                                              |
--! |----------|------|------------------------------------------------------|
--! | 0        | 7-6  | Duty cycle (12.5%, 25%, 50% or 75%)                  |
--! | 0        | 5-0  | Envelope (see @ref envelope_unit)                    |
--! | 1        | 7    | Sweep enable                                         |
--! | 1        | 6-4  | Sweep period                                         |
--! | 1        | 3    | Sweep direction: 1 to lower the period (`DEC`)       |
--! | 1        | 2-0  | Sweep shift (`SR`)                                   |
--! | 2        | 7-0  | Period, low byte                                     |
--! | 3        | 7-3  | Length (see @ref length_counter)                     |
--! | 3        | 2-0  | Period, high bits                                    |
--!
--! **Frequency.** The 11-bit period register (`Fx`) loads an 11-bit
--! @ref apu_counter "down counter", which steps every APU cycle and reloads
--! when it reaches zero, so it reloads every period + 1 APU cycles
--! (`FLOAD`). Each reload steps the 3-bit duty counter, which counts down
--! from 0 after a write to register 3. The duty cycle picks which of its
--! eight values let the output through:
--!
--! | Duty counter | 12.5% | 25% | 50% | 75% |
--! |--------------|-------|-----|-----|-----|
--! | 7            | 1     | 1   | 1   | 0   |
--! | 6            | 0     | 1   | 1   | 0   |
--! | 5-4          | 0     | 0   | 1   | 1   |
--! | 3-0          | 0     | 0   | 0   | 1   |
--!
--! **Sweep.** A barrel shifter shifts the period right by `SR` (inverting it
--! first when `DEC` is set), and an adder adds the result to the period. The
--! sum is latched during ACLK1. Every half frame
--! (@ref Ricoh_2A03_Signal_LFO2) steps a 3-bit sweep counter, which reloads
--! from the sweep period when it reaches zero, or after a write to register 1.
--! When it reaches zero, and the sweep is enabled, `SR` isn't zero and the
--! channel isn't silenced, the half frame copies the latched sum into the
--! period register (`DO_SWEEP`).
--!
--! The two channels' adders differ in their carry in. Square 0's is tied
--! low, so lowering the period subtracts one more than the shifted period
--! (ones' complement). Square 1's is `DEC`, so it subtracts exactly the
--! shifted period (two's complement). The `negate_carry_DEC` generic picks
--! which.
--!
--! **Muting.** The output is silenced, whatever the sweep settings:
--!
--! - while the period's bits 10-2 are all zero, so the period is below 4
--!   (`SW_UVF`),
--! - while raising the period would overflow 11 bits (`SW_OVF`), and
--! - while the length counter has finished
--!   (@ref Ricoh_2A03_Signal_NOxx).
--!
--! Otherwise the output is the envelope's volume while the duty cycle lets it
--! through, as latched during ACLK1. While @ref Ricoh_2A03_Signal_LOCK is
--! set, the output is the volume all the time.
--!
--! **The sweep loop.** On the die, the barrel shifter, the adder and the
--! `SW_UVF` gate read `Fx`, which is the period register except during
--! `DO_SWEEP`, when it's the latched sum. But `DO_SWEEP` itself depends on
--! `SW_OVF` and `SW_UVF`, so that's a combinational loop. When the swept
--! period's own next target would overflow (`$500` rising by shift 1 to
--! `$780`, whose next target is `$B40`), `DO_SWEEP` turns itself off, which
--! turns it back on, and the simulation never settles. This entity feeds them
--! from the period register instead. The sum latch only opens during ACLK1,
--! when `DO_SWEEP` is low, so it latches the same sum. The only difference is
--! that during `DO_SWEEP` the mute conditions are judged on the period before
--! the sweep, which is what the documentation describes.
--!
--! The die also drives the adder and the barrel shifter from both polarities
--! of the period, which only disagree during `DO_SWEEP`. This entity keeps
--! one. Every latch is sampled on the @ref metaclock while its enable is
--! high.
entity square_channel is
    generic(
        --! `true` for square 1, whose adder's carry in is `DEC`; `false` for
        --! square 0, whose carry in is tied low
        negate_carry_DEC: boolean := false
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
        --! Register 0 write (`W4000` or `W4004`)
        write_control_WR0: in std_ulogic;
        --! Register 1 write (`W4001` or `W4005`)
        write_sweep_WR1: in std_ulogic;
        --! Register 2 write (`W4002` or `W4006`)
        write_period_low_WR2: in std_ulogic;
        --! Register 3 write (`W4003` or `W4007`)
        write_period_high_WR3: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_LFO1
        quarter_frame_LFO1: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_LFO2
        half_frame_LFO2: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_NOxx, from the channel's
        --! @ref length_counter
        silenced_NOSQ: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_LOCK
        debug_lock_LOCK: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_xx_LC, to the channel's
        --! @ref length_counter
        length_carry_LC: out std_ulogic;
        --! The channel's output (`SQA` or `SQB`), for the DAC
        output_SQ: out std_ulogic_vector(3 downto 0);
        --! @ref metaclock
        metaclock: in std_ulogic
    );
end entity square_channel;

architecture rtl of square_channel is
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
    for frequency_counter: apu_counter use entity work.apu_counter;
    for sweep_counter: apu_counter use entity work.apu_counter;
    for duty_counter: apu_counter use entity work.apu_counter;
    for envelope: envelope_unit use entity work.envelope_unit;

    -- #region Registers
    --! Register 0, bits 7-6: the duty cycle (`DT`)
    signal duty_register: std_ulogic_vector(1 downto 0) := (others => '0');
    --! Register 1, bit 7: the sweep is enabled (`SWDIS` is its inverse)
    signal sweep_enabled: std_ulogic := '0';
    --! Register 1, bits 6-4: the sweep period
    signal sweep_period: std_ulogic_vector(2 downto 0) := (others => '0');
    --! Register 1, bit 3: lower the period (`DEC`)
    signal DEC: std_ulogic := '0';
    --! Register 1, bits 2-0: the sweep shift (`SR`)
    signal SR: std_ulogic_vector(2 downto 0) := (others => '0');
    --! Registers 2 and 3: the period register
    signal period_register: std_ulogic_vector(10 downto 0) := (others => '0');
    -- #endregion

    -- #region Frequency and duty
    --! `Fx`: the period, or the latched sum during `DO_SWEEP`
    signal Fx: std_ulogic_vector(10 downto 0);
    --! The frequency counter's carry out (`FCO`)
    signal frequency_done: std_ulogic;
    --! `FCO`, latched during ACLK1
    signal frequency_done_latch: std_ulogic := '0';
    --! `FLOAD`: reload the frequency counter, and step the duty counter
    signal FLOAD: std_ulogic;
    --! `FSTEP`: step the frequency counter
    signal FSTEP: std_ulogic;
    --! The duty counter (`DC`)
    signal duty_count: std_ulogic_vector(2 downto 0);
    --! The duty cycle lets the output through (`DUTY`)
    signal DUTY: std_ulogic;
    -- #endregion

    -- #region Sweep
    --! The barrel shifter's output (`S`)
    signal shifted: std_ulogic_vector(10 downto 0);
    --! The adder's carry in
    signal adder_carry_in: unsigned(0 downto 0);
    --! The adder's sum, with its carry out in bit 11
    signal sum: unsigned(11 downto 0);
    --! The sum, latched during ACLK1
    signal sum_latch: std_ulogic_vector(10 downto 0) := (others => '0');
    --! `SW_UVF`: the period is below 4
    signal SW_UVF: std_ulogic;
    --! `SW_OVF`: raising the period would overflow
    signal SW_OVF: std_ulogic;
    --! The sweep reload flag: set by a write to register 1, cleared by the
    --! half frame after it
    signal sweep_reload: std_ulogic := '0';
    --! The sweep reload flag, latched during ACLK1 (`SWRELOAD`)
    signal SWRELOAD: std_ulogic := '0';
    --! The sweep counter's carry out (`SCO`)
    signal sweep_done: std_ulogic;
    --! `SCO`, latched during ACLK1
    signal sweep_done_latch: std_ulogic := '0';
    --! `SLOAD`: reload the sweep counter
    signal SLOAD: std_ulogic;
    --! `SSTEP`: step the sweep counter
    signal SSTEP: std_ulogic;
    --! `DO_SWEEP`: copy the latched sum into the period register
    signal DO_SWEEP: std_ulogic;
    -- #endregion

    -- #region Output
    --! The output gate, latched during ACLK1
    signal output_latch: std_ulogic := '0';
    --! The envelope's volume (`V`)
    signal volume: std_ulogic_vector(3 downto 0);
    -- #endregion
begin
    envelope: envelope_unit
        port map(
            aclk1 => aclk1,
            reset_RES => reset_RES,
            bus_DB_in => bus_DB_in,
            write_control => write_control_WR0,
            write_length => write_period_high_WR3,
            quarter_frame_LFO1 => quarter_frame_LFO1,
            volume => volume,
            length_carry_LC => length_carry_LC,
            metaclock => metaclock
        );

    frequency_counter: apu_counter
        generic map(width => 11)
        port map(
            clock => aclk1,
            load => FLOAD,
            clear => reset_RES,
            step => FSTEP,
            carry_in => '1',
            count_down => '1',
            value_in => Fx,
            value_out => open,
            carry_out => frequency_done,
            metaclock => metaclock
        );

    duty_counter: apu_counter
        generic map(width => 3)
        port map(
            clock => aclk1,
            load => write_period_high_WR3,
            clear => reset_RES,
            step => FLOAD,
            carry_in => '1',
            count_down => '1',
            value_in => "000",
            value_out => duty_count,
            carry_out => open,
            metaclock => metaclock
        );

    sweep_counter: apu_counter
        generic map(width => 3)
        port map(
            clock => aclk1,
            load => SLOAD,
            clear => reset_RES,
            step => SSTEP,
            carry_in => '1',
            count_down => '1',
            value_in => sweep_period,
            value_out => open,
            carry_out => sweep_done,
            metaclock => metaclock
        );

    -- Frequency and duty
    Fx <= sum_latch when DO_SWEEP = '1' else period_register;
    FLOAD <= aclk2 and frequency_done_latch;
    FSTEP <= aclk2 and not frequency_done_latch;

    with duty_register select DUTY <=
        duty_count(0) and duty_count(1) and duty_count(2) when "00",
        duty_count(1) and duty_count(2) when "01",
        duty_count(2) when "10",
        not (duty_count(1) and duty_count(2)) when others;

    -- Sweep: the barrel shifter shifts in DEC from the top. It, the adder and
    -- SW_UVF read the period register rather than Fx (see above).
    barrel_shifter: process(period_register, DEC, SR)
        variable source: std_ulogic_vector(11 downto 0);
    begin
        if DEC = '1' then
            source := DEC & not period_register;
        else
            source := DEC & period_register;
        end if;
        for i in 0 to 10 loop
            if i + to_integer(unsigned(SR)) <= 11 then
                shifted(i) <= source(i + to_integer(unsigned(SR)));
            else
                shifted(i) <= DEC;
            end if;
        end loop;
    end process;

    adder_carry_in(0) <= DEC when negate_carry_DEC else '0';
    sum <= resize(unsigned(period_register), 12) + resize(unsigned(shifted), 12)
        + resize(adder_carry_in, 12);
    SW_OVF <= sum(11) and not DEC;
    SW_UVF <= '1' when period_register(10 downto 2) = "000000000" else '0';

    SSTEP <= half_frame_LFO2 and not SWRELOAD and not sweep_done_latch;
    SLOAD <= half_frame_LFO2 and (SWRELOAD or sweep_done_latch);
    DO_SWEEP <= half_frame_LFO2 and sweep_done_latch and sweep_enabled
        and not silenced_NOSQ and not SW_OVF and not SW_UVF
        when SR /= "000" else '0';

    process(metaclock)
    begin
        if rising_edge(metaclock) then
            if write_control_WR0 = '1' then
                duty_register <= bus_DB_in(7 downto 6);
            end if;

            if write_sweep_WR1 = '1' then
                sweep_enabled <= bus_DB_in(7);
                sweep_period <= bus_DB_in(6 downto 4);
                DEC <= bus_DB_in(3);
                SR <= bus_DB_in(2 downto 0);
            end if;

            -- The period register's node: written by the CPU during Phi2, or
            -- refreshed from Fx during ACLK2, which is the sum during
            -- DO_SWEEP
            if write_period_low_WR2 = '1' then
                period_register(7 downto 0) <= bus_DB_in;
            elsif aclk2 = '1' then
                period_register(7 downto 0) <= Fx(7 downto 0);
            end if;
            if write_period_high_WR3 = '1' then
                period_register(10 downto 8) <= bus_DB_in(2 downto 0);
            elsif aclk2 = '1' then
                period_register(10 downto 8) <= Fx(10 downto 8);
            end if;

            if write_sweep_WR1 = '1' then
                sweep_reload <= '1';
            elsif half_frame_LFO2 = '1' and SWRELOAD = '1' then
                sweep_reload <= '0';
            end if;

            if aclk1 = '1' then
                sum_latch <= std_ulogic_vector(sum(10 downto 0));
                frequency_done_latch <= frequency_done;
                SWRELOAD <= sweep_reload;
                sweep_done_latch <= sweep_done;
                output_latch <= DUTY and not SW_UVF and not silenced_NOSQ
                    and not SW_OVF;
            end if;
        end if;
    end process;

    output_SQ <= volume when output_latch = '1' or debug_lock_LOCK = '1'
        else "0000";
end architecture rtl;
