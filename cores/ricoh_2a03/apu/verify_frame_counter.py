"""Tests for the frame counter (`frame_counter`), against the documented
NTSC timings.

The frame counter restarts 3 or 4 CPU cycles after a write to $4017,
depending on which half of an APU cycle the write lands in. Counting from the
restart, in CPU cycles:

- 4-step mode: quarter frames at 7457, 14913, 22371 and 29829, half frames at
  14913 and 29829, the interrupt flag set from 29828, and a period of 29830.
- 5-step mode: quarter frames at 7457, 14913, 22371 and 37281, half frames at
  14913 and 37281, no interrupt, and a period of 37282. The write itself also
  clocks both, at the restart.
"""

from typing import TYPE_CHECKING

import cocotb

from cores.ricoh_2a03.apu_clock import ApuClock

if TYPE_CHECKING:
    from frame_counter import FrameCounter as DUT

QUARTER = "quarter_frame_LFO1"
HALF = "half_frame_LFO2"
FOUR_STEP_QUARTERS = [7457, 14913, 22371, 29829]
FOUR_STEP_HALVES = [14913, 29829]
FOUR_STEP_PERIOD = 29830
FIVE_STEP_QUARTERS = [7457, 14913, 22371, 37281]
FIVE_STEP_HALVES = [14913, 37281]
FIVE_STEP_PERIOD = 37282


async def setup(dut: "DUT") -> ApuClock:
    clock = ApuClock(dut, watch=(QUARTER, HALF, "interrupt_INT"))
    dut.reset_RES.value = 1
    dut.bus_DB_in.value = 0
    dut.write_W4017.value = 0
    dut.read_R4015.value = 0
    dut.dmc_interrupt_DMCINT.value = 0
    await clock.start()
    await clock.cycles_(4)
    dut.reset_RES.value = 0
    await clock.cycles_(3)
    return clock


async def write_4017(clock: ApuClock, value: int) -> int:
    """Write $4017, and return the cycle number of the write."""
    write_cycle = clock.cycles
    await clock.write("write_W4017", value)
    for pulses in clock.pulses.values():
        pulses.clear()
    return write_cycle


def restart_of(clock: ApuClock, write_cycle: int, first_quarter: int) -> int:
    """Find the restart from the first quarter frame, and check it's 3 or 4
    cycles after the write."""
    restart = first_quarter - 7457
    delay = restart - write_cycle
    assert delay in (3, 4), f"Restarted {delay} cycles after the $4017 write"
    return restart


@cocotb.test()
async def test_four_step_mode(dut: "DUT"):
    """4-step mode clocks the quarter and half frames at the documented cycles,
    sets the interrupt flag, and repeats every 29830 cycles."""
    clock = await setup(dut)
    write_cycle = await write_4017(clock, 0x00)
    await clock.cycles_(FOUR_STEP_PERIOD + 7500)

    quarters = clock.pulses[QUARTER]
    restart = restart_of(clock, write_cycle, quarters[0])
    expected = [restart + c for c in FOUR_STEP_QUARTERS]
    expected.append(restart + FOUR_STEP_PERIOD + FOUR_STEP_QUARTERS[0])
    assert quarters == expected, f"Quarter frames at {[q - restart for q in quarters]}"
    halves = clock.pulses[HALF]
    assert halves == [restart + c for c in FOUR_STEP_HALVES], (
        f"Half frames at {[h - restart for h in halves]}"
    )
    interrupt = clock.pulses["interrupt_INT"]
    assert interrupt, "The interrupt flag never set"
    assert interrupt[0] == restart + 29828, f"Interrupt set at {interrupt[0] - restart}"
    assert interrupt[-1] == clock.cycles - 1, "The interrupt flag didn't stay set"


@cocotb.test()
async def test_five_step_mode(dut: "DUT"):
    """5-step mode clocks both straight away, then at the documented cycles,
    repeats every 37282 cycles, and never interrupts."""
    clock = await setup(dut)
    write_cycle = await write_4017(clock, 0x80)
    await clock.cycles_(FIVE_STEP_PERIOD + 7500)

    quarters = clock.pulses[QUARTER]
    restart = restart_of(clock, write_cycle, quarters[1])
    immediate = quarters[0]
    assert immediate == restart - 1, f"The write clocked at {immediate - write_cycle} cycles after it"
    expected = [immediate] + [restart + c for c in FIVE_STEP_QUARTERS]
    expected.append(restart + FIVE_STEP_PERIOD + FIVE_STEP_QUARTERS[0])
    assert quarters == expected, f"Quarter frames at {[q - restart for q in quarters]}"
    halves = clock.pulses[HALF]
    assert halves == [immediate] + [restart + c for c in FIVE_STEP_HALVES], (
        f"Half frames at {[h - restart for h in halves]}"
    )
    assert clock.pulses["interrupt_INT"] == [], "Interrupted in 5-step mode"


@cocotb.test()
async def test_restart_depends_on_write_cycle(dut: "DUT"):
    """A write in one half of an APU cycle restarts the counter one CPU cycle
    sooner than a write in the other."""
    clock = await setup(dut)
    delays = []
    for _ in range(2):
        write_cycle = await write_4017(clock, 0x00)
        await clock.cycles_(7470)
        delays.append(restart_of(clock, write_cycle, clock.pulses[QUARTER][0]) - write_cycle)
        # The write and the 7470 cycles after it are an odd number of cycles,
        # so the next write lands in the other half of an APU cycle
    assert sorted(delays) == [3, 4], f"Restart delays {delays}"


@cocotb.test()
async def test_interrupt_read_and_inhibit(dut: "DUT"):
    """$4015 bit 6 reads the interrupt flag, and reading clears it. Setting
    the inhibit bit clears it too, and keeps it clear."""
    clock = await setup(dut)
    await write_4017(clock, 0x00)
    await clock.cycles_(29840)
    assert dut.interrupt_INT.value == 1, "The interrupt flag isn't set"

    # The read sees the flag, and clears it during Phi2
    dut.read_R4015.value = 1
    await clock.cycle()
    assert dut.bus_DB_out.value == 0xFF, "Bit 6 didn't read the flag"
    dut.read_R4015.value = 0
    assert dut.interrupt_INT.value == 0, "Reading $4015 didn't clear the flag"
    await clock.cycles_(2)
    dut.read_R4015.value = 1
    await clock.cycle()
    assert dut.bus_DB_out.value == 0xBF, "Bit 6 still reads set after clearing"
    dut.read_R4015.value = 0

    # Inhibited, the flag stays clear through the next 29830 cycles
    await write_4017(clock, 0x40)
    await clock.cycles_(29840)
    assert clock.pulses["interrupt_INT"] == [], "Interrupted with the inhibit bit set"


@cocotb.test()
async def test_dmc_interrupt_passes_through(dut: "DUT"):
    """INT is the frame interrupt ORed with the DMC's."""
    clock = await setup(dut)
    await write_4017(clock, 0x40)
    await clock.cycle()
    assert dut.interrupt_INT.value == 0
    dut.dmc_interrupt_DMCINT.value = 1
    await clock.cycle()
    assert dut.interrupt_INT.value == 1, "DMCINT didn't reach INT"
    dut.dmc_interrupt_DMCINT.value = 0
    await clock.cycle()
    assert dut.interrupt_INT.value == 0
