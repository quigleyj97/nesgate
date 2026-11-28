"""Tests for a square channel (`square_channel`), against the documented
behaviour.

The testbench runs twice: as square 0 (the default) and as square 1
(`negate_carry_DEC` true), whose sweeps differ when lowering the period.

A square channel's waveform is 8 sequencer steps of 2 × (period + 1) CPU
cycles each. From the sequencer reset (a write to register 3) the steps go:

| Duty | Waveform        |
|------|-----------------|
| 0    | 0 1 0 0 0 0 0 0 |
| 1    | 0 1 1 0 0 0 0 0 |
| 2    | 0 1 1 1 1 0 0 0 |
| 3    | 1 0 0 1 1 1 1 1 |
"""

import os
from typing import TYPE_CHECKING

import cocotb

from cores.ricoh_2a03.apu_clock import ApuClock

if TYPE_CHECKING:
    from square_channel import SquareChannel as DUT

IS_SQUARE_1 = os.environ.get("GENERIC_negate_carry_DEC", "false").lower() == "true"
WAVEFORMS = {
    0: [0, 1, 0, 0, 0, 0, 0, 0],
    1: [0, 1, 1, 0, 0, 0, 0, 0],
    2: [0, 1, 1, 1, 1, 0, 0, 0],
    3: [1, 0, 0, 1, 1, 1, 1, 1],
}


async def setup(dut: "DUT") -> ApuClock:
    clock = ApuClock(dut)
    dut.reset_RES.value = 1
    for name in ("write_control_WR0", "write_sweep_WR1", "write_period_low_WR2",
                 "write_period_high_WR3", "quarter_frame_LFO1", "half_frame_LFO2",
                 "silenced_NOSQ", "debug_lock_LOCK"):
        getattr(dut, name).value = 0
    dut.bus_DB_in.value = 0
    await clock.start()
    await clock.cycles_(4)
    dut.reset_RES.value = 0
    await clock.cycles_(2)
    return clock


async def configure(clock: ApuClock, duty: int, volume: int, period: int, sweep: int = 0):
    """Set a constant volume, the sweep, and the period, resetting the
    sequencer."""
    await clock.write("write_control_WR0", (duty << 6) | 0x10 | volume)
    await clock.write("write_sweep_WR1", sweep)
    await clock.write("write_period_low_WR2", period & 0xFF)
    await clock.write("write_period_high_WR3", period >> 8)


async def sample(dut: "DUT", clock: ApuClock, cycles: int) -> list[int]:
    samples = []
    for _ in range(cycles):
        await clock.cycle()
        samples.append(int(dut.output_SQ.value))
    return samples


def runs(samples: list[int]) -> list[tuple[int, int]]:
    """Run-length encode the samples, as (value, length) pairs."""
    encoded: list[tuple[int, int]] = []
    for value in samples:
        if encoded and encoded[-1][0] == value:
            encoded[-1] = (value, encoded[-1][1] + 1)
        else:
            encoded.append((value, 1))
    return encoded


def waveform_runs(duty: int, step: int, volume: int) -> list[tuple[int, int]]:
    return runs([volume * level for level in WAVEFORMS[duty] for _ in range(step)])


async def half_frame(clock: ApuClock):
    await clock.apu_cycle(aclk2={"half_frame_LFO2": 1})
    await clock.apu_cycle()


@cocotb.test()
async def test_duty_cycles(dut: "DUT"):
    """Each duty cycle's waveform repeats every 8 steps of 2 × (period + 1)
    CPU cycles, high for the documented number of steps. After the sequencer
    reset, duties 0-2 start low, then go high for their whole high part."""
    clock = await setup(dut)
    for duty in range(4):
        high_steps = sum(WAVEFORMS[duty])
        for period in (8, 21):
            step = 2 * (period + 1)
            # Start from silence, so the first run is the new waveform's
            await configure(clock, duty=2, volume=0, period=0)
            await clock.cycles_(8)
            await configure(clock, duty, volume=11, period=period)
            samples = await sample(dut, clock, 8 * step * 3)

            if duty < 3:
                got = runs(samples)
                assert got[0][0] == 0, f"Duty {duty}: started high"
                assert got[1] == (11, high_steps * step), (
                    f"Duty {duty}, period {period}: first high run {got[1]}"
                )

            last, before = samples[-8 * step:], samples[-16 * step:-8 * step]
            assert last == before, f"Duty {duty}, period {period}: doesn't repeat every 8 steps"
            assert last.count(11) == high_steps * step, (
                f"Duty {duty}, period {period}: high for {last.count(11)} of {8 * step} cycles"
            )
            # One high run and one low run per waveform, going round
            while last[0] == last[-1]:
                last = last[1:] + last[:1]
            assert len(runs(last)) == 2, f"Duty {duty}, period {period}: {runs(last)}"


@cocotb.test()
async def test_low_periods_muted(dut: "DUT"):
    """Periods 0-3 are muted. Period 8 is not."""
    clock = await setup(dut)
    for period in range(4):
        await configure(clock, duty=2, volume=15, period=period)
        assert set(await sample(dut, clock, 200)) == {0}, f"Period {period} wasn't muted"
    await configure(clock, duty=2, volume=15, period=8)
    assert 15 in await sample(dut, clock, 200), "Period 8 was muted"


@cocotb.test()
async def test_length_counter_silences(dut: "DUT"):
    """The output is 0 while the length counter has finished."""
    clock = await setup(dut)
    await configure(clock, duty=2, volume=15, period=20)
    dut.silenced_NOSQ.value = 1
    assert set(await sample(dut, clock, 200)) == {0}, "Not silenced"
    dut.silenced_NOSQ.value = 0
    assert 15 in await sample(dut, clock, 200), "Still silent"


@cocotb.test()
async def test_lock(dut: "DUT"):
    """While LOCK is set the output is the volume all the time."""
    clock = await setup(dut)
    await configure(clock, duty=0, volume=6, period=20)
    dut.debug_lock_LOCK.value = 1
    assert set(await sample(dut, clock, 400)) == {6}, "LOCK didn't hold the volume"
    dut.debug_lock_LOCK.value = 0


@cocotb.test()
async def test_sweep_lowers_period(dut: "DUT"):
    """Lowering the period subtracts the shifted period, and one more on
    square 0 (ones' complement)."""
    clock = await setup(dut)
    # Enabled, sweep period 0, negate, shift 1
    await configure(clock, duty=2, volume=15, period=0x100, sweep=0x89)
    await half_frame(clock)
    expected = 0x80 if IS_SQUARE_1 else 0x7F
    period = int(dut.period_register.value)
    assert period == expected, f"Lowered 0x100 to {period:#x}, expected {expected:#x}"


@cocotb.test()
async def test_sweep_raises_period(dut: "DUT"):
    """Raising the period adds the shifted period, every sweep period + 1 half
    frames."""
    clock = await setup(dut)
    # Enabled, sweep period 2, raise, shift 2
    await configure(clock, duty=2, volume=15, period=0x100, sweep=0xA2)
    periods = []
    for _ in range(7):
        await half_frame(clock)
        periods.append(int(dut.period_register.value))
    # The sweep counter starts at 0, so the first half frame sweeps and
    # reloads it, then it sweeps every third
    assert periods == [0x140, 0x140, 0x140, 0x190, 0x190, 0x190, 0x1F4], (
        f"Got {[hex(p) for p in periods]}"
    )


@cocotb.test()
async def test_sweep_up_to_overflow(dut: "DUT"):
    """A sweep whose result's own target would overflow still applies, and
    then the channel is muted: $500 rises to $780, whose next target ($B40)
    is above $7FF."""
    clock = await setup(dut)
    # Enabled, sweep period 0, raise, shift 1
    await configure(clock, duty=2, volume=15, period=0x500, sweep=0x81)
    # A whole waveform is 16 × (period + 1) cycles
    assert 15 in await sample(dut, clock, 16 * 0x501), "Muted before the sweep"
    await half_frame(clock)
    period = int(dut.period_register.value)
    assert period == 0x780, f"Swept $500 to {period:#x}, expected 0x780"
    assert set(await sample(dut, clock, 16 * 0x781)) == {0}, "Not muted after the sweep"
    await half_frame(clock)
    assert int(dut.period_register.value) == 0x780, "Swept past $7FF"


@cocotb.test()
async def test_sweep_needs_shift_and_enable(dut: "DUT"):
    """The period doesn't change with a shift of 0, or the sweep disabled."""
    clock = await setup(dut)
    for sweep in (0x80, 0x01):
        await configure(clock, duty=2, volume=15, period=0x100, sweep=sweep)
        for _ in range(3):
            await half_frame(clock)
        assert int(dut.period_register.value) == 0x100, f"Sweep {sweep:#x} changed the period"


@cocotb.test()
async def test_overflow_mutes(dut: "DUT"):
    """A target period above $7FF mutes the channel, even with the sweep
    disabled, and the sweep doesn't apply it."""
    clock = await setup(dut)
    # Shift 0 doubles the period: $400 + $400 overflows
    await configure(clock, duty=2, volume=15, period=0x400, sweep=0x00)
    assert set(await sample(dut, clock, 200)) == {0}, "Period $400 with shift 0 wasn't muted"
    # Enabled, raising $7FF by $3FF overflows
    await configure(clock, duty=2, volume=15, period=0x7FF, sweep=0x81)
    assert set(await sample(dut, clock, 200)) == {0}, "Overflowing sweep wasn't muted"
    await half_frame(clock)
    assert int(dut.period_register.value) == 0x7FF, "The overflowing sweep was applied"
    # $3FF + $1FF doesn't overflow
    await configure(clock, duty=2, volume=15, period=0x3FF, sweep=0x01)
    assert 15 in await sample(dut, clock, 200), "Muted without overflowing"


@cocotb.test()
async def test_length_carry(dut: "DUT"):
    """The length counter's carry is register 0's bit 5, inverted."""
    clock = await setup(dut)
    await clock.write("write_control_WR0", 0x20)
    assert dut.length_carry_LC.value == 0
    await clock.write("write_control_WR0", 0x00)
    assert dut.length_carry_LC.value == 1
