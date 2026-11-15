from typing import TYPE_CHECKING

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

if TYPE_CHECKING:
    from predecode_register import PredecodeRegister as DUT

@cocotb.test()
async def test_predecode_register(dut: "DUT"):
    """The register follows the data bus during Phi2 and holds it otherwise"""

    cocotb.start_soon(Clock(dut.metaclock, 1, unit="ns").start())

    dut.phi2.value = 0
    dut.data_in.value = 0xA9
    await ClockCycles(dut.metaclock, 2)
    assert dut.predecode_out.value == 0x00, "Loaded while Phi2 was low"

    # Transparent while Phi2 is high: follows the bus as it settles
    dut.phi2.value = 1
    await ClockCycles(dut.metaclock, 2)
    assert dut.predecode_out.value == 0xA9, "Did not load during Phi2"
    dut.data_in.value = 0xEA
    await ClockCycles(dut.metaclock, 2)
    assert dut.predecode_out.value == 0xEA, "Did not follow the bus during Phi2"

    # Holds the last value once Phi2 falls
    dut.phi2.value = 0
    await ClockCycles(dut.metaclock, 1)
    dut.data_in.value = 0x00
    await ClockCycles(dut.metaclock, 2)
    assert dut.predecode_out.value == 0xEA, "Did not hold its value after Phi2"
