from typing import TYPE_CHECKING

import cocotb
from cocotb.triggers import Timer
from cocotb.types import LogicArray

if TYPE_CHECKING:
    from adh_open_drain_mosfet import AdhOpenDrainMosfet as DUT

@cocotb.test()
async def test_adh_open_drain_mosfet(dut: "DUT"):
    """Test the ADH open drain MOSFET functionality"""
    
    # Initialize signals
    dut.signal_0_ADH0.value = 0
    dut.signal_0_ADH_1_7.value = 0
    
    # Wait for signals to propagate
    await Timer(1, unit='ns')
    
    # Check initial state - all high-impedance (represented by X in sim)
    expected = LogicArray("ZZZZZZZZ")
    assert dut.adh_bus.value == expected, f"Initial state should be high-Z but got {dut.adh_bus.value}"
    
    # Test signal_0_ADH0 asserted - bit 0 should be low, others high-Z
    dut.signal_0_ADH0.value = 1
    await Timer(1, unit='ns')
    expected = LogicArray("ZZZZZZZ0")
    assert dut.adh_bus.value == expected, f"When signal_0_ADH0=1, only bit 0 should be low, got {dut.adh_bus.value}"
    
    # Test signal_0_ADH_1_7 asserted - bits 1-7 should be low, bit 0 high-Z
    dut.signal_0_ADH0.value = 0
    dut.signal_0_ADH_1_7.value = 1
    await Timer(1, unit='ns')
    expected = LogicArray("0000000Z")
    assert dut.adh_bus.value == expected, f"When signal_0_ADH_1_7=1, bits 1-7 should be low, got {dut.adh_bus.value}"
    
    # Test both signals asserted - all bits should be low
    dut.signal_0_ADH0.value = 1
    dut.signal_0_ADH_1_7.value = 1
    await Timer(1, unit='ns')
    expected = LogicArray("00000000")
    assert dut.adh_bus.value == expected, f"When both signals=1, all bits should be low, got {dut.adh_bus.value}"
    
    # Test signals de-asserted - all bits high-Z again
    dut.signal_0_ADH0.value = 0
    dut.signal_0_ADH_1_7.value = 0
    await Timer(1, unit='ns')
    expected = LogicArray("ZZZZZZZZ")
    assert dut.adh_bus.value == expected, f"Final state should be high-Z but got {dut.adh_bus.value}"