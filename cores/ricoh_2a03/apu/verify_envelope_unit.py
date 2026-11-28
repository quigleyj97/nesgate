"""Tests for the envelope unit (`envelope_unit`), against the documented
envelope behaviour.

After a write to the length register, the next quarter frame starts the
envelope at 15. From then on it drops by one every period + 1 quarter frames,
and at 0 it stays, or goes back to 15 if it loops. With constant volume, the
output is just the volume bits.
"""

from typing import TYPE_CHECKING

import cocotb

from cores.ricoh_2a03.apu_clock import ApuClock

if TYPE_CHECKING:
    from envelope_unit import EnvelopeUnit as DUT


async def setup(dut: "DUT") -> ApuClock:
    clock = ApuClock(dut)
    dut.reset_RES.value = 1
    dut.bus_DB_in.value = 0
    dut.write_control.value = 0
    dut.write_length.value = 0
    dut.quarter_frame_LFO1.value = 0
    await clock.start()
    await clock.cycles_(4)
    dut.reset_RES.value = 0
    await clock.cycles_(2)
    return clock


async def quarter_frames(dut: "DUT", clock: ApuClock, count: int) -> list[int]:
    """Run `count` quarter frames, and return the volume after each."""
    volumes = []
    for _ in range(count):
        await clock.apu_cycle(aclk2={"quarter_frame_LFO1": 1})
        await clock.apu_cycle()
        volumes.append(int(dut.volume.value))
    return volumes


def expected_decay(period: int, count: int, loop: bool) -> list[int]:
    volumes = []
    level = 15
    divider = period
    for frame in range(count):
        if frame > 0:
            if divider == 0:
                divider = period
                if level > 0:
                    level -= 1
                elif loop:
                    level = 15
            else:
                divider -= 1
        volumes.append(level)
    return volumes


@cocotb.test()
async def test_constant_volume(dut: "DUT"):
    """With bit 4 set, the volume is bits 3-0, and quarter frames don't
    change it."""
    clock = await setup(dut)
    await clock.write("write_control", 0x19)
    assert dut.volume.value == 9
    await clock.write("write_length", 0)
    assert await quarter_frames(dut, clock, 3) == [9, 9, 9]


@cocotb.test()
async def test_decay(dut: "DUT"):
    """Without loop, the envelope runs from 15 down to 0, one step every
    period + 1 quarter frames, and stays there."""
    clock = await setup(dut)
    for period in (0, 2):
        await clock.write("write_control", period)
        await clock.write("write_length", 0)
        count = 16 * (period + 1) + 4
        volumes = await quarter_frames(dut, clock, count)
        assert volumes == expected_decay(period, count, loop=False), f"Period {period}: {volumes}"


@cocotb.test()
async def test_loop(dut: "DUT"):
    """With loop, the envelope goes back to 15 after 0."""
    clock = await setup(dut)
    await clock.write("write_control", 0x21)
    await clock.write("write_length", 0)
    volumes = await quarter_frames(dut, clock, 40)
    assert volumes == expected_decay(1, 40, loop=True), f"{volumes}"


@cocotb.test()
async def test_restart(dut: "DUT"):
    """A write to the length register restarts the envelope at 15."""
    clock = await setup(dut)
    await clock.write("write_control", 0x00)
    await clock.write("write_length", 0)
    await quarter_frames(dut, clock, 5)
    assert dut.volume.value == 11
    await clock.write("write_length", 0)
    assert await quarter_frames(dut, clock, 2) == [15, 14]


@cocotb.test()
async def test_length_carry(dut: "DUT"):
    """The length counter's carry is bit 5, inverted."""
    clock = await setup(dut)
    await clock.write("write_control", 0x20)
    assert dut.length_carry_LC.value == 0
    await clock.write("write_control", 0x1F)
    assert dut.length_carry_LC.value == 1
