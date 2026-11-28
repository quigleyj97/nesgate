"""Tests for the I/O ports (`io_ports`)."""

from typing import TYPE_CHECKING

import cocotb

from cores.ricoh_2a03.apu_clock import ApuClock

if TYPE_CHECKING:
    from io_ports import IoPorts as DUT


async def setup(dut: "DUT") -> ApuClock:
    clock = ApuClock(dut)
    dut.bus_DB_in.value = 0
    dut.write_W4016.value = 0
    dut.read_R4016.value = 0
    dut.read_R4017.value = 0
    await clock.start()
    await clock.cycles_(2)
    await clock.write("write_W4016", 0)
    await clock.cycles_(2)
    return clock


@cocotb.test()
async def test_out_pins_change_at_aclk2(dut: "DUT"):
    """Writing $4016 sets OUT0-OUT2 from bits 2-0, at the next ACLK2."""
    clock = await setup(dut)
    for value in (0b101, 0b010, 0b111):
        # Write in the ACLK2 cycle, so the next ACLK2 is two cycles away
        if not clock.next_is_aclk1:
            await clock.cycle()
        await clock.cycle()
        await clock.write("write_W4016", 0xF8 | value)
        assert dut.out_pins_OUT.value != value, "Changed before ACLK2"
        await clock.cycle()
        assert dut.out_pins_OUT.value != value, "Changed at ACLK1"
        await clock.cycle()
        assert dut.out_pins_OUT.value == value, f"OUT is {dut.out_pins_OUT.value}, expected {value:03b}"


@cocotb.test()
async def test_in_strobes(dut: "DUT"):
    """/IN0 and /IN1 are low while reading $4016 and $4017."""
    clock = await setup(dut)
    assert (dut.in0_pin_n_IN0.value, dut.in1_pin_n_IN1.value) == (1, 1)
    dut.read_R4016.value = 1
    await clock.cycle()
    assert (dut.in0_pin_n_IN0.value, dut.in1_pin_n_IN1.value) == (0, 1)
    dut.read_R4016.value = 0
    dut.read_R4017.value = 1
    await clock.cycle()
    assert (dut.in0_pin_n_IN0.value, dut.in1_pin_n_IN1.value) == (1, 0)
    dut.read_R4017.value = 0
