from typing import TYPE_CHECKING

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer

if TYPE_CHECKING:
    from data_input_latch import DataInputLatch as DUT


@cocotb.test()
async def test_data_input_latch(dut: "DUT"):
    """The latch follows the data pins while load (Phi2) is high, keeps the
    last value, and drives DB, ADH and ADL when enabled."""
    cocotb.start_soon(Clock(dut.metaclock, 1, unit="ns").start())
    dut.data_in.value = 0x00
    dut.load.value = 0
    dut.db_bus_enable_DL_DB.value = 0
    dut.adh_bus_enable_DL_ADH.value = 0
    dut.adl_bus_enable_DL_ADL.value = 0
    await Timer(1, unit="ns")
    dut.load.value = 1
    await Timer(2, unit="ns")
    dut.data_in.value = 0x96
    await Timer(2, unit="ns")
    dut.load.value = 0
    await Timer(1, unit="ns")
    dut.data_in.value = 0x00
    await Timer(2, unit="ns")
    assert dut.register_data.value == 0x96

    # Assert that the register outputs open bus when the enable signals are low
    assert dut.db_bus_port.value == 0xFF
    assert dut.adh_bus_port.value == 0xFF
    assert dut.adl_bus_port.value == 0xFF

    dut.db_bus_enable_DL_DB.value = 1
    await Timer(1, unit="ns")
    assert dut.db_bus_port.value == 0x96
    dut.db_bus_enable_DL_DB.value = 0

    dut.adh_bus_enable_DL_ADH.value = 1
    await Timer(1, unit="ns")
    assert dut.adh_bus_port.value == 0x96
    assert dut.db_bus_port.value == 0xFF
    dut.adh_bus_enable_DL_ADH.value = 0

    dut.adl_bus_enable_DL_ADL.value = 1
    await Timer(1, unit="ns")
    assert dut.adl_bus_port.value == 0x96
    assert dut.adh_bus_port.value == 0xFF
