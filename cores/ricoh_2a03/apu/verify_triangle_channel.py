"""Tests for the triangle channel (`triangle_channel`), against the documented
behaviour.

The triangle steps through 15, 14, ..., 0, 0, 1, ..., 15 once every period + 1
CPU cycles, while both the linear counter and the length counter are
non-zero. When either stops it, the output holds its level.
"""

import itertools
from typing import TYPE_CHECKING

import cocotb

from cores.ricoh_2a03.apu_clock import ApuClock

if TYPE_CHECKING:
    from triangle_channel import TriangleChannel as DUT

async def setup(dut: "DUT") -> ApuClock:
    clock = ApuClock(dut)
    dut.reset_RES.value = 1
    for name in ("write_W4008", "write_W400A", "write_W400B", "write_W401A",
                 "quarter_frame_LFO1", "silenced_NOTRI", "debug_lock_LOCK"):
        getattr(dut, name).value = 0
    dut.bus_DB_in.value = 0
    await clock.start()
    await clock.cycles_(4)
    dut.reset_RES.value = 0
    await clock.cycles_(2)
    return clock


async def quarter_frame(clock: ApuClock):
    await clock.apu_cycle(aclk2={"quarter_frame_LFO1": 1})


async def start(clock: ApuClock, period: int, linear: int = 0x7F, control: bool = True):
    await clock.write("write_W4008", (0x80 if control else 0) | linear)
    await clock.write("write_W400A", period & 0xFF)
    await clock.write("write_W400B", period >> 8)
    await quarter_frame(clock)


async def sample(dut: "DUT", clock: ApuClock, cycles: int) -> list[int]:
    samples = []
    for _ in range(cycles):
        await clock.cycle()
        samples.append(int(dut.output_TRI.value))
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


def changes(samples: list[int]) -> list[tuple[int, int]]:
    """(cycle, value) for each change of value."""
    return [(i, v) for i, v in enumerate(samples) if i > 0 and v != samples[i - 1]]


@cocotb.test()
async def test_sequence_and_period(dut: "DUT"):
    """The output runs through the triangle sequence, one step every
    period + 1 CPU cycles. 0 and 15 come twice in a row, so they last twice
    as long."""
    clock = await setup(dut)
    for period in (3, 10):
        await start(clock, period)
        samples = await sample(dut, clock, 70 * (period + 1))
        # Drop the first and last runs, which can be cut short
        got = runs(samples)[1:-1]
        assert len(got) > 40, f"Period {period}: only {len(got)} steps"
        for (value, length), (next_value, _) in itertools.pairwise(got):
            assert abs(next_value - value) == 1, f"Period {period}: {value} then {next_value}"
            expected = 2 * (period + 1) if value in (0, 15) else period + 1
            assert length == expected, f"Period {period}: {value} lasted {length}"
        # It turns round only at 0 and 15
        for (a, _), (b, _), (c, _) in zip(got, got[1:], got[2:]):
            if a == c:
                assert b in (0, 15), f"Period {period}: turned round at {b}"


@cocotb.test()
async def test_starts_at_15(dut: "DUT"):
    """From reset, the sequence starts at 15 and steps down."""
    clock = await setup(dut)
    assert dut.output_TRI.value == 15
    await start(clock, 5)
    values = [v for _, v in changes(await sample(dut, clock, 40))]
    assert values[:4] == [14, 13, 12, 11], f"Got {values}"


@cocotb.test()
async def test_linear_counter(dut: "DUT"):
    """With the control bit clear, the linear counter stops the channel after
    reload value + 1 quarter frames, and the output holds its level."""
    clock = await setup(dut)
    await start(clock, period=2, linear=3, control=False)
    for _ in range(3):
        assert len(changes(await sample(dut, clock, 30))) > 0, "Stopped too soon"
        await quarter_frame(clock)
    held = await sample(dut, clock, 60)
    assert len(set(held)) == 1, f"Kept stepping after the linear counter ran out: {held}"


@cocotb.test()
async def test_control_keeps_reloading(dut: "DUT"):
    """With the control bit set, every quarter frame reloads the linear
    counter, so it never stops the channel."""
    clock = await setup(dut)
    await start(clock, period=2, linear=1, control=True)
    for _ in range(5):
        await quarter_frame(clock)
    assert len(changes(await sample(dut, clock, 30))) > 0, "Stopped with the control bit set"


@cocotb.test()
async def test_length_counter_stops(dut: "DUT"):
    """When the length counter has finished, the output holds its level."""
    clock = await setup(dut)
    await start(clock, period=2)
    dut.silenced_NOTRI.value = 1
    await clock.cycles_(2)
    assert len(set(await sample(dut, clock, 60))) == 1, "Stepped with NOTRI set"
    dut.silenced_NOTRI.value = 0
    assert len(changes(await sample(dut, clock, 30))) > 0, "Didn't carry on"


@cocotb.test()
async def test_lock_and_debug_load(dut: "DUT"):
    """LOCK stops the output, and a debug write to $401A loads the step."""
    clock = await setup(dut)
    await start(clock, period=2)
    dut.debug_lock_LOCK.value = 1
    await clock.write("write_W401A", 0x10)
    assert int(dut.output_TRI.value) == 0, "Step 16 isn't 0"
    assert set(await sample(dut, clock, 60)) == {0}, "Stepped with LOCK set"
    dut.debug_lock_LOCK.value = 0


@cocotb.test()
async def test_length_carry(dut: "DUT"):
    """The length counter's carry is the control bit, inverted."""
    clock = await setup(dut)
    await clock.write("write_W4008", 0x80)
    assert dut.length_carry_LC.value == 0
    await clock.write("write_W4008", 0x7F)
    assert dut.length_carry_LC.value == 1
