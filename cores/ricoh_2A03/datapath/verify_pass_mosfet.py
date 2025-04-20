import cocotb
from cocotb.triggers import Timer
from cocotb.handle import SimHandleBase

@cocotb.test()
async def test_pass_mosfet(dut: SimHandleBase):
    """Test the pass MOSFET functionality"""
    
    # Initialize test values
    test_value_1 = 0b10101010
    test_value_2 = 0b11001100
    
    # Initially both buses should be in high impedance state
    dut.enable.value = 0
    await Timer(1, units="fs")
    
    # Check that buses are in high impedance (not resolved)
    assert not dut.bus_1.value.is_resolvable
    assert not dut.bus_2.value.is_resolvable
    
    # Test bus_1 to bus_2 connection when enabled
    dut.enable.value = 1
    dut.bus_1.value = test_value_1
    await Timer(1, units="fs")
    
    assert dut.bus_2.value == test_value_1, f"Expected bus_2 value to be {test_value_1}, got {dut.bus_2.value}"
    
    # Test bus_2 to bus_1 connection when enabled
    dut.bus_2.value = test_value_2
    await Timer(1, units="fs")
    
    assert dut.bus_1.value == test_value_2, f"Expected bus_1 value to be {test_value_2}, got {dut.bus_1.value}"
    
    # Test isolation when disabled
    dut.enable.value = 0
    await Timer(1, units="fs")
    
    # Both buses should be in high impedance state when disabled
    assert not dut.bus_1.value.is_resolvable
    assert not dut.bus_2.value.is_resolvable
    
    # Ensure one bus doesn't affect the other when disabled
    dut.bus_1.value = test_value_1
    await Timer(1, units="fs")
    
    assert not dut.bus_2.value.is_resolvable, "bus_2 should be in high impedance when disabled"