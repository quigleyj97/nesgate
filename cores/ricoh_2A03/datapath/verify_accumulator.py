from typing import TYPE_CHECKING

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer

if TYPE_CHECKING:
    from accumulator import Accumulator as DUT


async def setup(dut: "DUT"):
    cocotb.start_soon(Clock(dut.metaclock, 1, unit="ns").start())
    dut.load_SB_AC.value = 0
    dut.output_enable_AC_DB.value = 0
    dut.output_enable_AC_SB.value = 0
    await Timer(1, unit="ns")


@cocotb.test()
async def test_accumulator_register(dut: "DUT"):
    """The accumulator loads from SB while SB/AC is asserted, and drives SB and DB."""
    await setup(dut)
    dut.databus_SB_in.value = 0x5A
    dut.load_SB_AC.value = 1
    await Timer(4, unit="ns")
    dut.load_SB_AC.value = 0
    await Timer(1, unit="ns")
    assert dut.register_data.value == 0x5A
    assert not dut.databus_DB.value.is_resolvable
    assert not dut.databus_SB_out.value.is_resolvable

    dut.output_enable_AC_DB.value = 1
    await Timer(1, unit="ns")
    assert dut.databus_DB.value == 0x5A
    dut.output_enable_AC_DB.value = 0
    dut.output_enable_AC_SB.value = 1
    await Timer(1, unit="ns")
    assert dut.databus_SB_out.value == 0x5A


@cocotb.test()
async def test_accumulator_keeps_last_value(dut: "DUT"):
    """While SB/AC is asserted the accumulator follows SB, and keeps the last
    value it saw, not the first."""
    await setup(dut)
    dut.databus_SB_in.value = 0xFF
    dut.load_SB_AC.value = 1
    await Timer(2, unit="ns")
    dut.databus_SB_in.value = 0x3C
    await Timer(2, unit="ns")
    dut.load_SB_AC.value = 0
    await Timer(1, unit="ns")
    dut.databus_SB_in.value = 0x00
    await Timer(2, unit="ns")
    assert dut.register_data.value == 0x3C
