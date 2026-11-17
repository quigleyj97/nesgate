from typing import TYPE_CHECKING

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer

if TYPE_CHECKING:
    from index_register import IndexRegister as DUT


async def setup(dut: "DUT"):
    cocotb.start_soon(Clock(dut.metaclock, 1, unit="ns").start())
    dut.load.value = 0
    dut.output_enable.value = 0
    await Timer(1, unit="ns")


@cocotb.test()
async def test_index_register(dut: "DUT"):
    """The register loads while load is asserted, and drives its output when enabled."""
    await setup(dut)
    dut.data_in.value = 0xA5
    dut.load.value = 1
    await Timer(4, unit="ns")
    dut.load.value = 0
    await Timer(1, unit="ns")
    assert dut.register_data.value == 0xA5

    # Assert that the register outputs open bus when the enable signal is low
    assert not dut.data_out.value.is_resolvable

    dut.output_enable.value = 1
    await Timer(1, unit="ns")
    assert dut.data_out.value == 0xA5


@cocotb.test()
async def test_index_register_holds(dut: "DUT"):
    """The register keeps the last value it saw while load was asserted."""
    await setup(dut)
    dut.data_in.value = 0x11
    dut.load.value = 1
    await Timer(2, unit="ns")
    dut.data_in.value = 0x22
    await Timer(2, unit="ns")
    dut.load.value = 0
    await Timer(1, unit="ns")
    dut.data_in.value = 0x33
    await Timer(2, unit="ns")
    assert dut.register_data.value == 0x22
