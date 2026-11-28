"""Tests for the noise channel (`noise_channel`), against the documented
behaviour.

The noise channel's random LFSR steps once every timer period, which the
period index picks from the documented NTSC table. Each step it shifts right,
feeding bit 0 XOR bit 1 (bit 6 in mode 1) into bit 14. The output is the
volume while bit 0 is clear.
"""

import itertools
from typing import TYPE_CHECKING

import cocotb

from cores.ricoh_2a03.apu_clock import ApuClock

if TYPE_CHECKING:
    from noise_channel import NoiseChannel as DUT

#: The timer period for each index, in CPU cycles
PERIODS = [4, 8, 16, 32, 64, 96, 128, 160, 202, 254, 380, 508, 762, 1016, 2034, 4068]


async def setup(dut: "DUT") -> ApuClock:
    clock = ApuClock(dut, watch=("NFLOAD",))
    dut.reset_RES.value = 1
    for name in ("write_W400C", "write_W400E", "write_W400F", "quarter_frame_LFO1",
                 "silenced_NORND", "debug_lock_LOCK"):
        getattr(dut, name).value = 0
    dut.bus_DB_in.value = 0
    await clock.start()
    await clock.cycles_(4)
    dut.reset_RES.value = 0
    await clock.cycles_(2)
    # Constant volume 9
    await clock.write("write_W400C", 0x19)
    return clock


async def steps(dut: "DUT", clock: ApuClock, count: int) -> list[int]:
    """Run until the random LFSR has stepped `count` times, and return the
    output after each step."""
    outputs = []
    pulses = clock.pulses["NFLOAD"]
    while len(outputs) < count:
        before = len(pulses)
        await clock.cycle()
        if len(pulses) > before:
            # The output latch picks up the step at the next ACLK1
            await clock.cycle()
            outputs.append(int(dut.output_RND.value))
    return outputs


def reference(state: int, mode: int, count: int) -> list[int]:
    """The documented LFSR: return bit 0 after each of `count` steps."""
    bits = []
    for _ in range(count):
        tap = (state >> (6 if mode else 1)) & 1
        feedback = (state & 1) ^ tap
        state = (state >> 1) | (feedback << 14)
        bits.append(state & 1)
    return bits


@cocotb.test()
async def test_timer_periods(dut: "DUT"):
    """Each period index steps the LFSR at the documented rate."""
    clock = await setup(dut)
    pulses = clock.pulses["NFLOAD"]
    for index, period in enumerate(PERIODS):
        await clock.write("write_W400E", index)
        # The timer finishes its old period before loading the new one
        pulses.clear()
        while len(pulses) < 4:
            await clock.cycle()
        gaps = [b - a for a, b in itertools.pairwise(pulses[1:])]
        assert gaps == [period, period], f"Index {index}: steps every {gaps}, expected {period}"


@cocotb.test()
async def test_random_sequence(dut: "DUT"):
    """In both modes, the output follows the documented LFSR."""
    clock = await setup(dut)
    for mode in (0, 1):
        await clock.write("write_W400E", (mode << 7) | 0)
        await steps(dut, clock, 2)
        state = int(dut.random_lfsr.value)
        expected = [9 * (1 - bit) for bit in reference(state, mode, 200)]
        got = await steps(dut, clock, 200)
        assert got == expected, f"Mode {mode}, from {state:#06x}: {got[:20]} expected {expected[:20]}"


@cocotb.test()
async def test_mode_1_repeats_every_93(dut: "DUT"):
    """Mode 1's sequence repeats every 93 steps."""
    clock = await setup(dut)
    await clock.write("write_W400E", 0x80)
    await steps(dut, clock, 200)
    got = await steps(dut, clock, 93 * 3)
    assert got[:93] == got[93:186] == got[186:], "Mode 1 doesn't repeat every 93 steps"
    assert got[:31] != got[31:62], "Mode 1 repeats every 31 steps"


@cocotb.test()
async def test_silenced(dut: "DUT"):
    """The output is 0 while the length counter has finished."""
    clock = await setup(dut)
    dut.silenced_NORND.value = 1
    assert set(await steps(dut, clock, 30)) == {0}, "Not silenced"
    dut.silenced_NORND.value = 0
    assert 9 in await steps(dut, clock, 30)
