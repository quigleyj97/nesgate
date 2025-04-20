import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer
from cocotb.binary import BinaryValue
from cocotb.handle import Force

@cocotb.test()
async def test_program_counter_low_reset(dut):
    """Test that program counter starts at zero after initialization"""
    
    clock = Clock(dut.phi2, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    # Default state - all control signals inactive
    dut.signal_PCL_DB.value = 0
    dut.signal_PCL_ADL.value = 0
    dut.signal_1_PC.value = 0
    dut.signal_PCL_PCL.value = 0
    dut.signal_ADL_PCL.value = 0
    
    # Set bus values to high-impedance
    dut.bus_ADL.value = BinaryValue("zzzzzzzz")
    dut.bus_DB.value = BinaryValue("zzzzzzzz")
    
    await RisingEdge(dut.phi2)
    await FallingEdge(dut.phi2)
    
    # Verify initial state - program_counter_register should be 0
    dut.signal_PCL_DB.value = 1
    await Timer(1, units="ns")
    assert dut.bus_DB.value == 0, f"Expected PCL to be 0, got {dut.bus_DB.value}"

@cocotb.test()
async def test_program_counter_increment(dut):
    """Test program counter increment operation"""
    
    clock = Clock(dut.phi2, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    # Initialize all control signals
    dut.signal_PCL_DB.value = 0
    dut.signal_PCL_ADL.value = 0
    dut.signal_1_PC.value = 0
    dut.signal_PCL_PCL.value = 0
    dut.signal_ADL_PCL.value = 0
    dut.bus_ADL.value = BinaryValue("zzzzzzzz")
    dut.bus_DB.value = BinaryValue("zzzzzzzz")
    
    # First clock cycle - set up PCL_PCL to store PC value in select register
    dut.signal_PCL_PCL.value = 1
    await RisingEdge(dut.phi2)
    await FallingEdge(dut.phi2)
    
    # Second clock cycle - increment the counter
    dut.signal_PCL_PCL.value = 0
    dut.signal_1_PC.value = 1
    await RisingEdge(dut.phi2)
    await FallingEdge(dut.phi2)
    
    # Verify counter incremented to 1
    dut.signal_PCL_DB.value = 1
    await Timer(1, units="ns")
    assert dut.bus_DB.value == 1, f"Expected PCL to be 1 after increment, got {dut.bus_DB.value}"
    assert dut.signal_PCLC.value == 0, "Expected no carry out"
    
    # Increment again
    dut.signal_PCL_DB.value = 0
    dut.signal_PCL_PCL.value = 1
    await RisingEdge(dut.phi2)
    await FallingEdge(dut.phi2)
    
    # Verify counter incremented to 2
    dut.signal_PCL_DB.value = 1
    await Timer(1, units="ns")
    assert dut.bus_DB.value == 2, f"Expected PCL to be 2 after increment, got {dut.bus_DB.value}"

@cocotb.test()
async def test_program_counter_load_from_adl(dut):
    """Test loading PCL from address low bus"""
    
    clock = Clock(dut.phi2, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    # Initialize all control signals
    dut.signal_PCL_DB.value = 0
    dut.signal_PCL_ADL.value = 0
    dut.signal_1_PC.value = 0
    dut.signal_PCL_PCL.value = 0
    dut.signal_ADL_PCL.value = 0
    dut.bus_ADL.value = BinaryValue("zzzzzzzz")
    dut.bus_DB.value = BinaryValue("zzzzzzzz")
    
    # Load a value from ADL to PCL
    dut.bus_ADL.value = 0x42
    dut.signal_ADL_PCL.value = 1
    await Timer(1, units="ns")
    
    # Clock in the value
    await RisingEdge(dut.phi2)
    dut.signal_ADL_PCL.value = 0
    await FallingEdge(dut.phi2)
    
    # Verify the value was loaded
    dut.signal_PCL_DB.value = 1
    await Timer(1, units="ns")
    assert dut.bus_DB.value == 0x42, f"Expected PCL to be 0x42 after load, got {dut.bus_DB.value}"

@cocotb.test()
async def test_program_counter_output_to_buses(dut):
    """Test PCL outputs to both DB and ADL buses"""
    
    clock = Clock(dut.phi2, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    # Initialize all control signals
    dut.signal_PCL_DB.value = 0
    dut.signal_PCL_ADL.value = 0
    dut.signal_1_PC.value = 0
    dut.signal_PCL_PCL.value = 0
    dut.signal_ADL_PCL.value = 0
    dut.bus_ADL.value = BinaryValue("zzzzzzzz")
    dut.bus_DB.value = BinaryValue("zzzzzzzz")
    
    # Load test value 0xA5 to PCL
    dut.bus_ADL.value = 0xA5
    dut.signal_ADL_PCL.value = 1
    await Timer(1, units="ns")
    
    # Clock in the value
    await RisingEdge(dut.phi2)
    dut.signal_ADL_PCL.value = 0
    await FallingEdge(dut.phi2)
    
    # Test output to DB
    dut.signal_PCL_DB.value = 1
    await Timer(1, units="ns")
    assert dut.bus_DB.value == 0xA5, f"Expected DB to be 0xA5, got {dut.bus_DB.value}"
    
    # Test output to ADL
    dut.signal_PCL_DB.value = 0
    dut.signal_PCL_ADL.value = 1
    await Timer(1, units="ns")
    assert dut.bus_ADL.value == 0xA5, f"Expected ADL to be 0xA5, got {dut.bus_ADL.value}"

@cocotb.test()
async def test_carry_out(dut):
    """Test carry out signal when PCL overflows from 0xFF to 0x00"""
    
    clock = Clock(dut.phi2, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    # Initialize all control signals
    dut.signal_PCL_DB.value = 0
    dut.signal_PCL_ADL.value = 0
    dut.signal_1_PC.value = 0
    dut.signal_PCL_PCL.value = 0
    dut.signal_ADL_PCL.value = 0
    dut.bus_DB.value = BinaryValue("zzzzzzzz")
    
    # Load 0xFF to PCL
    dut.bus_ADL.value = Force(0xFF)
    await Timer(1, units="ns")
    dut.signal_ADL_PCL.value = 1
    await Timer(1, units="ns")
    
    # Clock in the value
    await RisingEdge(dut.phi2)
    dut.signal_ADL_PCL.value = 0
    await FallingEdge(dut.phi2)
    
    # Set up PCL_PCL to store PC value in select register
    dut.signal_PCL_PCL.value = 1
    await RisingEdge(dut.phi2)
    await FallingEdge(dut.phi2)
    
    # Increment the counter
    dut.signal_PCL_PCL.value = 0
    dut.signal_1_PC.value = 1
    await Timer(1, units="ns")
    
    # Check carry out is asserted
    assert dut.signal_PCLC.value == 1, "Expected carry out signal to be asserted"
    
    # Clock in the incremented value
    await RisingEdge(dut.phi2)
    await FallingEdge(dut.phi2)
    
    # Verify counter wrapped to 0
    dut.signal_PCL_DB.value = 1
    await Timer(1, units="ns")
    assert dut.bus_DB.value == 0x00, f"Expected PCL to be 0x00 after overflow, got {dut.bus_DB.value}"