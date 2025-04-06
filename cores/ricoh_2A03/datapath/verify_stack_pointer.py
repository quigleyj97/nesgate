import cocotb
from cocotb.triggers import Timer
from cocotb.handle import SimHandleBase

@cocotb.test()
async def test_stack_pointer(dut: SimHandleBase):
    """Test the stack pointer behavior"""

    # Initialize inputs
    dut.signal_S_SB.value = 0
    dut.signal_S_ADL.value = 0
    dut.signal_SB_S.value = 0
    dut.bus_SB.value = 0b00000000
    dut.bus_ADL.value = 0b00000000
    await Timer(1, units="ns")

    # Test loading a value into the stack pointer from bus_SB
    dut.bus_SB.value = 0b10101010
    dut.signal_SB_S.value = 1  # Enable loading from bus_SB
    await Timer(1, units="ns")
    dut.signal_SB_S.value = 0  # Disable loading
    await Timer(1, units="ns")
    assert dut.register_value.value == 0b10101010, "Stack pointer did not load the correct value from bus_SB"

    # Test outputting the stack pointer value to bus_SB
    dut.signal_S_SB.value = 1  # Enable output to bus_SB
    await Timer(1, units="ns")
    assert dut.bus_SB.value == 0b10101010, "Stack pointer did not output the correct value to bus_SB"
    dut.signal_S_SB.value = 0  # Disable output
    await Timer(1, units="ns")
    assert not dut.bus_SB.value.is_resolvable, "bus_SB should be open when signal_S_SB is low"

    # Test outputting the stack pointer value to bus_ADL
    dut.signal_S_ADL.value = 1  # Enable output to bus_ADL
    await Timer(1, units="ns")
    assert dut.bus_ADL.value == 0b10101010, "Stack pointer did not output the correct value to bus_ADL"
    dut.signal_S_ADL.value = 0  # Disable output
    await Timer(1, units="ns")
    assert not dut.bus_ADL.value.is_resolvable, "bus_ADL should be open when signal_S_ADL is low"

    # Test that the stack pointer retains its value when no signals are active
    dut.signal_S_SB.value = 0
    dut.signal_S_ADL.value = 0
    dut.bus_SB.value = 0b11111111  # Change bus_SB to ensure no unintended loading
    await Timer(1, units="ns")
    assert dut.register_value.value == 0b10101010, "Stack pointer value changed unexpectedly"
