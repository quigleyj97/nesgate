"""Tests for a length counter (`length_counter`), with its default status
bit, 0 (square 0).

A loaded length counter silences its channel after that many half frames,
unless the channel halts it, and only while the channel is enabled in $4015.
"""

from typing import TYPE_CHECKING

import cocotb

from cores.ricoh_2a03.apu_clock import ApuClock

if TYPE_CHECKING:
    from length_counter import LengthCounter as DUT


async def setup(dut: "DUT") -> ApuClock:
    clock = ApuClock(dut)
    dut.reset_RES.value = 1
    dut.bus_DB_in.value = 0
    dut.write_length.value = 0
    dut.write_W4015.value = 0
    dut.read_R4015.value = 0
    dut.length_value.value = 0
    dut.half_frame_LFO2.value = 0
    dut.length_carry_LC.value = 1
    await clock.start()
    await clock.cycles_(4)
    dut.reset_RES.value = 0
    await clock.cycles_(2)
    return clock


async def enable(clock: ApuClock, enabled: bool):
    await clock.write("write_W4015", 0x01 if enabled else 0x00)


async def load(clock: ApuClock, length: int):
    """Load a length, as the length decoder would (one less)."""
    await clock.cycle(phi2={"write_length": 1, "length_value": length - 1})


async def half_frames_until_silenced(dut: "DUT", clock: ApuClock, limit: int = 300) -> int | None:
    for count in range(1, limit + 1):
        await clock.apu_cycle(aclk2={"half_frame_LFO2": 1})
        await clock.apu_cycle()
        if dut.silenced_NO.value == 1:
            return count
    return None


@cocotb.test()
async def test_silences_after_length(dut: "DUT"):
    """A channel is silenced after exactly its length in half frames."""
    clock = await setup(dut)
    await enable(clock, True)
    for length in (2, 10, 254):
        await load(clock, length)
        await clock.apu_cycle()
        assert dut.silenced_NO.value == 0, "Silenced straight after loading"
        count = await half_frames_until_silenced(dut, clock)
        assert count == length, f"Length {length} lasted {count} half frames"


@cocotb.test()
async def test_halt_holds(dut: "DUT"):
    """While the channel halts the counter, half frames don't count it down,
    and it carries on once released."""
    clock = await setup(dut)
    await enable(clock, True)
    await load(clock, 4)
    await clock.apu_cycle(aclk2={"half_frame_LFO2": 1})
    dut.length_carry_LC.value = 0
    assert await half_frames_until_silenced(dut, clock, limit=20) is None, "Counted while halted"
    dut.length_carry_LC.value = 1
    assert await half_frames_until_silenced(dut, clock) == 3, "Didn't carry on from 3"


@cocotb.test()
async def test_disable(dut: "DUT"):
    """Disabling the channel in $4015 silences it within an APU cycle, and
    loads while it's disabled don't take."""
    clock = await setup(dut)
    await enable(clock, True)
    await load(clock, 20)
    await clock.apu_cycle()
    assert dut.silenced_NO.value == 0
    await enable(clock, False)
    await clock.apu_cycle()
    assert dut.silenced_NO.value == 1, "Disabling didn't silence"
    await load(clock, 20)
    await clock.apu_cycle()
    assert dut.silenced_NO.value == 1, "A load stuck while disabled"


@cocotb.test()
async def test_status_read(dut: "DUT"):
    """Reading $4015 drives the channel's bit: set while counting."""
    clock = await setup(dut)
    dut.read_R4015.value = 1
    await clock.cycle()
    assert dut.bus_DB_out.value == 0xFE, "Bit 0 set before loading"
    await enable(clock, True)
    await load(clock, 10)
    await clock.cycle()
    assert dut.bus_DB_out.value == 0xFF, "Bit 0 clear while counting"
    dut.read_R4015.value = 0
    await clock.cycle()
    assert dut.bus_DB_out.value == 0xFF, "Drove the bus without a read"
