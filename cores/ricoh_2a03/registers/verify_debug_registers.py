"""Tests for the test mode registers (`debug_registers`)."""

from typing import TYPE_CHECKING

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, Timer

if TYPE_CHECKING:
    from debug_registers import DebugRegisters as DUT


async def setup(dut: "DUT"):
    dut.reset_RES.value = 0
    dut.bus_DB_in.value = 0
    dut.write_W401A.value = 0
    dut.read_R4018.value = 0
    dut.read_R4019.value = 0
    dut.read_R401A.value = 0
    dut.output_SQA.value = 0x3
    dut.output_SQB.value = 0xC
    dut.output_TRI.value = 0x5
    dut.output_RND.value = 0xA
    dut.output_DMC.value = 0x2B
    cocotb.start_soon(Clock(dut.metaclock, 2, unit="ns").start())
    await FallingEdge(dut.metaclock)


async def pulse(dut: "DUT", name: str, value: int = 0):
    dut.bus_DB_in.value = value
    getattr(dut, name).value = 1
    await Timer(8, unit="ns")
    getattr(dut, name).value = 0
    await Timer(1, unit="ns")


@cocotb.test()
async def test_reads(dut: "DUT"):
    """$4018-$401A read the channel outputs, and the bus is released
    otherwise."""
    await setup(dut)
    await Timer(1, unit="ns")
    assert dut.bus_DB_out.value == 0xFF, "Drove the bus without a read"
    for strobe, expected in (("read_R4018", 0xC3), ("read_R4019", 0xA5), ("read_R401A", 0xAB)):
        getattr(dut, strobe).value = 1
        await Timer(1, unit="ns")
        assert dut.bus_DB_out.value == expected, f"{strobe}: {int(dut.bus_DB_out.value):#04x}"
        getattr(dut, strobe).value = 0


@cocotb.test()
async def test_lock(dut: "DUT"):
    """Bit 7 of a $401A write sets LOCK, and clearing it or reset clears it."""
    await setup(dut)
    await pulse(dut, "write_W401A", 0x80)
    assert dut.debug_lock_LOCK.value == 1, "LOCK didn't set"
    await pulse(dut, "write_W401A", 0x7F)
    assert dut.debug_lock_LOCK.value == 0, "LOCK didn't clear"
    await pulse(dut, "write_W401A", 0x80)
    await pulse(dut, "reset_RES")
    assert dut.debug_lock_LOCK.value == 0, "Reset didn't clear LOCK"
