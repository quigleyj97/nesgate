import cocotb
from cocotb.triggers import Timer
from cocotb.handle import SimHandleBase

@cocotb.test()
async def test_precharge_mosfets(dut: SimHandleBase):
    """Test the precharge MOSFETs functionality"""
    
    # Test when phi2 is low (0)
    dut.phi2.value = 0
    await Timer(1, units="fs")
    
    # Check that bus is in high-Z state when phi2 is low
    assert not dut.bus.value.is_resolvable, "Bus should be in high-Z state when phi2 is low"
    
    # Test when phi2 is high (1)
    dut.phi2.value = 1
    await Timer(1, units="fs")
    
    # Check that all bits of the bus are high (1)
    assert dut.bus.value == 0xFF, f"All bits should be high (0xFF) when phi2 is high, got {dut.bus.value}"
    
    # Test transition back to phi2 low
    dut.phi2.value = 0
    await Timer(1, units="fs")
    
    # Check that bus is in high-Z state again
    assert not dut.bus.value.is_resolvable, "Bus should return to high-Z state when phi2 returns to low"