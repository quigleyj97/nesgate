from typing import TYPE_CHECKING

import cocotb
from cocotb.triggers import Timer

if TYPE_CHECKING:
    from precharge_mosfets import PrechargeMosfets as DUT

@cocotb.test()
async def test_precharge_mosfets(dut: "DUT"):
    """Test the precharge MOSFETs functionality"""
    
    # Test when phi2 is low (0)
    dut.phi2.value = 0
    await Timer(1, unit="fs")
    
    # Check that bus is in high-Z state when phi2 is low
    assert not dut.databus.value.is_resolvable, "Bus should be in high-Z state when phi2 is low"
    
    # Test when phi2 is high (1)
    dut.phi2.value = 1
    await Timer(1, unit="fs")
    
    # Check that all bits of the bus are high (1)
    assert dut.databus.value == 0xFF, f"All bits should be high (0xFF) when phi2 is high, got {dut.databus.value}"
    
    # Test transition back to phi2 low
    dut.phi2.value = 0
    await Timer(1, unit="fs")
    
    # Check that bus is in high-Z state again
    assert not dut.databus.value.is_resolvable, "Bus should return to high-Z state when phi2 returns to low"