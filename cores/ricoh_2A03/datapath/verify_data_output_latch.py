from typing import TYPE_CHECKING

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer

if TYPE_CHECKING:
    from data_output_latch import DataOutputLatch as DUT


@cocotb.test()
async def test_data_output_latch(dut: "DUT"):
    """The DOR loads DB during Phi1, and drives the pins only during Phi2 of a
    write cycle."""
    cocotb.start_soon(Clock(dut.metaclock, 1, unit="ns").start())
    dut.data_in.value = 0x00
    dut.phi1.value = 0
    dut.phi2.value = 0
    dut.signal_R_NOT_W.value = 1
    await Timer(1, unit="ns")

    # Phi1: the DOR follows DB and keeps the last value
    dut.phi1.value = 1
    await Timer(2, unit="ns")
    dut.data_in.value = 0xC7
    await Timer(2, unit="ns")
    dut.phi1.value = 0
    await Timer(1, unit="ns")
    dut.data_in.value = 0x00
    await Timer(1, unit="ns")
    assert dut.register_data.value == 0xC7
    assert not dut.data_out.value.is_resolvable

    # Reading: the pins stay released during Phi2
    dut.phi2.value = 1
    await Timer(1, unit="ns")
    assert not dut.data_out.value.is_resolvable
    dut.phi2.value = 0

    # Writing: the pins are only driven during Phi2
    dut.signal_R_NOT_W.value = 0
    await Timer(1, unit="ns")
    assert not dut.data_out.value.is_resolvable, "DOR should not drive outside Phi2"
    dut.phi2.value = 1
    await Timer(1, unit="ns")
    assert dut.data_out.value == 0xC7
    dut.phi2.value = 0
    await Timer(1, unit="ns")
    assert not dut.data_out.value.is_resolvable
