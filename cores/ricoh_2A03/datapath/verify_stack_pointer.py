from typing import TYPE_CHECKING

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Timer

if TYPE_CHECKING:
    from stack_pointer import StackPointer as DUT


async def setup(dut: "DUT"):
    cocotb.start_soon(Clock(dut.metaclock, 1, unit="ns").start())
    dut.phi2.value = 0
    dut.signal_S_SB.value = 0
    dut.signal_S_ADL.value = 0
    dut.signal_SB_S.value = 0
    dut.bus_SB_in.value = 0
    await Timer(1, unit="ns")


async def load(dut: "DUT", value: int):
    """Load S from SB during Phi1, and pass it to the outputs during Phi2."""
    dut.bus_SB_in.value = value
    dut.signal_SB_S.value = 1
    await ClockCycles(dut.metaclock, 2)
    dut.signal_SB_S.value = 0
    dut.phi2.value = 1
    await ClockCycles(dut.metaclock, 2)
    dut.phi2.value = 0
    await Timer(1, unit="ns")


@cocotb.test()
async def test_stack_pointer(dut: "DUT"):
    """S loads from SB, and drives SB and ADL."""
    await setup(dut)
    await load(dut, 0b10101010)
    assert dut.register_value.value == 0b10101010, "Stack pointer did not load the correct value from bus_SB"

    # Test outputting the stack pointer value to bus_SB
    dut.signal_S_SB.value = 1
    await Timer(1, unit="ns")
    assert dut.bus_SB_out.value == 0b10101010, "Stack pointer did not output the correct value to bus_SB"
    dut.signal_S_SB.value = 0
    await Timer(1, unit="ns")
    assert not dut.bus_SB_out.value.is_resolvable, "bus_SB should be open when signal_S_SB is low"

    # Test outputting the stack pointer value to bus_ADL
    dut.signal_S_ADL.value = 1
    await Timer(1, unit="ns")
    assert dut.bus_ADL.value == 0b10101010, "Stack pointer did not output the correct value to bus_ADL"
    dut.signal_S_ADL.value = 0
    await Timer(1, unit="ns")
    assert not dut.bus_ADL.value.is_resolvable, "bus_ADL should be open when signal_S_ADL is low"

    # Test that the stack pointer retains its value when no signals are active
    dut.bus_SB_in.value = 0b11111111
    dut.phi2.value = 1
    await ClockCycles(dut.metaclock, 2)
    dut.phi2.value = 0
    assert dut.register_value.value == 0b10101010, "Stack pointer value changed unexpectedly"


@cocotb.test()
async def test_outputs_old_value_while_loading(dut: "DUT"):
    """A value loaded during Phi1 only reaches the outputs in Phi2, so S can
    drive its old value while it loads a new one."""
    await setup(dut)
    await load(dut, 0xFF)

    dut.signal_S_ADL.value = 1
    dut.bus_SB_in.value = 0x12
    dut.signal_SB_S.value = 1
    await ClockCycles(dut.metaclock, 3)
    assert dut.bus_ADL.value == 0xFF, "S/ADL changed before Phi2"
    dut.signal_SB_S.value = 0
    dut.phi2.value = 1
    await ClockCycles(dut.metaclock, 2)
    dut.phi2.value = 0
    await Timer(1, unit="ns")
    assert dut.bus_ADL.value == 0x12, "The new value did not reach S/ADL during Phi2"
    dut.signal_S_ADL.value = 0
