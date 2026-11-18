from typing import TYPE_CHECKING

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Timer

if TYPE_CHECKING:
    from adder_hold_register import AdderHoldRegister as DUT

@cocotb.test()
async def test_adder_hold_register(dut: "DUT"):
    cocotb.start_soon(Clock(dut.metaclock, 1, unit="ns").start())

    # Verify the register can load a value
    dut.data_in.value = 0b00000000
    dut.load.value = False
    await ClockCycles(dut.metaclock, 1)
    dut.load.value = True
    await ClockCycles(dut.metaclock, 2)
    dut.load.value = False
    await ClockCycles(dut.metaclock, 1)
    assert dut.register_data.value == 0b00000000

    # Assert that the register outputs open bus when the enable signal is low
    assert not dut.sb_bus_port.value.is_resolvable
    assert not dut.adl_bus_port.value.is_resolvable

    dut.adl_bus_enable_ADD_ADL.value = True
    dut.sb_bus_enable_ADD_SB_0_6.value = True
    dut.sb_bus_enable_ADD_SB_7.value = True
    await Timer(1, unit="fs")

    assert dut.sb_bus_port.value == 0b00000000
    assert dut.adl_bus_port.value == 0b00000000

    # Verify the bit-level outputs when only parts of the SB bus output are enabled
    dut.sb_bus_enable_ADD_SB_0_6.value = False
    await Timer(1, unit="fs")
    assert str(dut.sb_bus_port.value).lower() == "0zzzzzzz"

    dut.sb_bus_enable_ADD_SB_0_6.value = True
    dut.sb_bus_enable_ADD_SB_7.value = False
    await Timer(1, unit="fs")

    assert str(dut.sb_bus_port.value).lower() == "z0000000"


@cocotb.test()
async def test_load_during_phi2(dut: "DUT"):
    """The register follows data_in while load (Phi2) is high, and keeps the
    value from the last metaclock edge of Phi2 once it falls."""
    cocotb.start_soon(Clock(dut.metaclock, 1, unit="ns").start())
    dut.adl_bus_enable_ADD_ADL.value = True
    dut.sb_bus_enable_ADD_SB_0_6.value = False
    dut.sb_bus_enable_ADD_SB_7.value = False

    dut.load.value = True
    dut.data_in.value = 0x12
    await ClockCycles(dut.metaclock, 2)
    await Timer(1, unit="ps")
    assert dut.adl_bus_port.value == 0x12

    # The input changes later in Phi2, and the register follows it
    dut.data_in.value = 0x34
    await ClockCycles(dut.metaclock, 2)
    await Timer(1, unit="ps")
    assert dut.adl_bus_port.value == 0x34

    # Phi2 ends: the input changes, but the register holds
    dut.load.value = False
    dut.data_in.value = 0x56
    await ClockCycles(dut.metaclock, 3)
    await Timer(1, unit="ps")
    assert dut.adl_bus_port.value == 0x34
