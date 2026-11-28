"""Tests for the APU's counter cell (`apu_counter`), at its default width of 8.

The counter computes its next value while `clock` is high, and moves to it on
`step`. These tests drive `clock` and `step` in alternate phases, as the APU
does (ACLK1, then ACLK2).
"""

from typing import TYPE_CHECKING

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, Timer

if TYPE_CHECKING:
    from apu_counter import ApuCounter as DUT

PHASE_NS = 8


async def setup(dut: "DUT", count_down: int = 1):
    dut.clock.value = 0
    dut.load.value = 0
    dut.clear.value = 0
    dut.step.value = 0
    dut.carry_in.value = 1
    dut.count_down.value = count_down
    dut.value_in.value = 0
    cocotb.start_soon(Clock(dut.metaclock, 2, unit="ns").start())
    await FallingEdge(dut.metaclock)


async def pulse(dut: "DUT", name: str):
    getattr(dut, name).value = 1
    await Timer(PHASE_NS, unit="ns")
    getattr(dut, name).value = 0
    await Timer(PHASE_NS, unit="ns")


async def load(dut: "DUT", value: int):
    dut.value_in.value = value
    await pulse(dut, "load")


async def count(dut: "DUT"):
    """One counting cycle: open the carry latches, then step."""
    await pulse(dut, "clock")
    await pulse(dut, "step")


@cocotb.test()
async def test_counts_down(dut: "DUT"):
    """Each clock-then-step cycle counts down by one."""
    await setup(dut)
    await load(dut, 5)
    assert dut.value_out.value == 5, "Didn't load"
    for expected in (4, 3, 2, 1, 0):
        await count(dut)
        assert dut.value_out.value == expected, f"Read {int(dut.value_out.value)}, expected {expected}"


@cocotb.test()
async def test_carry_out_at_zero_counting_down(dut: "DUT"):
    """Counting down, the carry out is set at zero, and the next step wraps."""
    await setup(dut)
    await load(dut, 1)
    assert dut.carry_out.value == 0, "Carry out set at 1"
    await count(dut)
    assert dut.carry_out.value == 1, "Carry out clear at 0"
    await count(dut)
    assert dut.value_out.value == 0xFF, "Didn't wrap from 0 to 0xFF"
    assert dut.carry_out.value == 0, "Carry out still set after wrapping"


@cocotb.test()
async def test_counts_up(dut: "DUT"):
    """With count_down low, it counts up, with the carry out set at 0xFF."""
    await setup(dut, count_down=0)
    await load(dut, 0xFD)
    await count(dut)
    assert dut.value_out.value == 0xFE
    assert dut.carry_out.value == 0, "Carry out set at 0xFE"
    await count(dut)
    assert dut.value_out.value == 0xFF
    assert dut.carry_out.value == 1, "Carry out clear at 0xFF"
    await count(dut)
    assert dut.value_out.value == 0x00, "Didn't wrap from 0xFF to 0"


@cocotb.test()
async def test_reverses(dut: "DUT"):
    """The direction can change between steps."""
    await setup(dut, count_down=0)
    await load(dut, 0x10)
    await count(dut)
    assert dut.value_out.value == 0x11
    dut.count_down.value = 1
    await count(dut)
    await count(dut)
    assert dut.value_out.value == 0x0F


@cocotb.test()
async def test_carry_in_low_holds(dut: "DUT"):
    """With the carry in low, a step leaves the value, and the carry out
    stays clear even at zero."""
    await setup(dut)
    await load(dut, 0)
    dut.carry_in.value = 0
    await Timer(1, unit="ns")
    assert dut.carry_out.value == 0, "Carry out set with carry in low"
    for _ in range(3):
        await count(dut)
    assert dut.value_out.value == 0, "Changed with carry in low"


@cocotb.test()
async def test_step_uses_last_clock(dut: "DUT"):
    """A step moves to the value worked out at the last clock, so a load
    between the clock and the step is overwritten by the old count."""
    await setup(dut)
    await load(dut, 9)
    await pulse(dut, "clock")  # carry latches: 8
    await load(dut, 3)
    assert dut.value_out.value == 3
    await pulse(dut, "step")
    assert dut.value_out.value == 8, "Step didn't use the carry latches from the last clock"


@cocotb.test()
async def test_steps_once_per_step(dut: "DUT"):
    """Holding step for a whole phase moves the counter once."""
    await setup(dut)
    await load(dut, 7)
    await pulse(dut, "clock")
    dut.step.value = 1
    await Timer(5 * PHASE_NS, unit="ns")
    dut.step.value = 0
    await Timer(1, unit="ns")
    assert dut.value_out.value == 6, "Stepped more than once"


@cocotb.test()
async def test_load_beats_clear_beats_step(dut: "DUT"):
    """Load beats clear, which beats step."""
    await setup(dut)
    await load(dut, 4)
    await pulse(dut, "clock")
    dut.value_in.value = 0x5A
    dut.load.value = 1
    dut.clear.value = 1
    dut.step.value = 1
    await Timer(PHASE_NS, unit="ns")
    assert dut.value_out.value == 0x5A, "Load didn't win"
    dut.load.value = 0
    await Timer(PHASE_NS, unit="ns")
    assert dut.value_out.value == 0, "Clear didn't beat step"
    dut.clear.value = 0
    dut.step.value = 0
