import cocotb
from cocotb.triggers import Timer
from cocotb.handle import SimHandleBase

@cocotb.test()
async def test_adl_open_drain_mosfet(dut: SimHandleBase):
    """Test the ADL open drain MOSFET functionality"""
    # Initialize all control signals to inactive
    dut.signal_0_ADL0.value = 0
    dut.signal_0_ADL1.value = 0
    dut.signal_0_ADL2.value = 0
    await Timer(1, units="fs")
    
    # Verify all bits are high-Z when signals are inactive
    for i in range(8):
        assert not dut.adl_bus[i].value.is_resolvable, f"Expected bit {i} to be high-Z when no signals active"
    
    # Test signal_0_ADL0 pulling bit 0 low
    dut.signal_0_ADL0.value = 1
    await Timer(1, units="fs")
    assert dut.adl_bus[0].value == 0, "Bit 0 should be pulled low when signal_0_ADL0 is active"
    for i in range(1, 8):
        assert not dut.adl_bus[i].value.is_resolvable, f"Expected bit {i} to be high-Z"
    
    # Reset and test signal_0_ADL1
    dut.signal_0_ADL0.value = 0
    dut.signal_0_ADL1.value = 1
    await Timer(1, units="fs")
    assert dut.adl_bus[1].value == 0, "Bit 1 should be pulled low when signal_0_ADL1 is active"
    assert not dut.adl_bus[0].value.is_resolvable, "Bit 0 should be high-Z when signal_0_ADL0 is inactive"
    for i in range(2, 8):
        assert not dut.adl_bus[i].value.is_resolvable, f"Expected bit {i} to be high-Z"
    
    # Reset and test signal_0_ADL2
    dut.signal_0_ADL1.value = 0
    dut.signal_0_ADL2.value = 1
    await Timer(1, units="fs")
    assert dut.adl_bus[2].value == 0, "Bit 2 should be pulled low when signal_0_ADL2 is active"
    for i in range(2):
        assert not dut.adl_bus[i].value.is_resolvable, f"Expected bit {i} to be high-Z"
    for i in range(3, 8):
        assert not dut.adl_bus[i].value.is_resolvable, f"Expected bit {i} to be high-Z"
    
    # Test multiple signals active simultaneously
    dut.signal_0_ADL0.value = 1
    dut.signal_0_ADL1.value = 1
    await Timer(1, units="fs")
    assert dut.adl_bus[0].value == 0, "Bit 0 should be pulled low when signal_0_ADL0 is active"
    assert dut.adl_bus[1].value == 0, "Bit 1 should be pulled low when signal_0_ADL1 is active"
    assert dut.adl_bus[2].value == 0, "Bit 2 should be pulled low when signal_0_ADL2 is active"
    for i in range(3, 8):
        assert not dut.adl_bus[i].value.is_resolvable, f"Expected bit {i} to be high-Z"
    
    # Test all signals active
    dut.signal_0_ADL0.value = 1
    dut.signal_0_ADL1.value = 1
    dut.signal_0_ADL2.value = 1
    await Timer(1, units="fs")
    assert dut.adl_bus[0].value == 0, "Bit 0 should be pulled low when signal_0_ADL0 is active"
    assert dut.adl_bus[1].value == 0, "Bit 1 should be pulled low when signal_0_ADL1 is active"
    assert dut.adl_bus[2].value == 0, "Bit 2 should be pulled low when signal_0_ADL2 is active"
    for i in range(3, 8):
        assert not dut.adl_bus[i].value.is_resolvable, f"Expected bit {i} to be high-Z"