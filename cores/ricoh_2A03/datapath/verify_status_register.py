import cocotb
from cocotb.handle import SimHandleBase
from cocotb.triggers import Timer

@cocotb.test()
async def test_status_register_data_bus(dut: SimHandleBase):
    # Verify the register can load a value
    set_signals_low(dut)
    dut.signal_DB0_C.value = True
    dut.signal_DB1_Z.value = True
    dut.signal_DB2_I.value = True
    dut.signal_DB3_D.value = True
    dut.signal_DB6_V.value = True
    dut.signal_DB7_N.value = True
    await Timer(1, units="fs")
    assert dut.register_data.value == 0b00000000
    assert dut.DBZ.value == True

    # Test that setting DB to all ones doesn't set every single bit
    dut.db_bus.value = 0b11111111
    await Timer(1, units="fs")
    assert dut.register_data.value == 0b11001111
    assert dut.DBZ.value == False

    # Test bus output
    await Timer(1, units="fs")
    dut.signal_DB0_C.value = False
    dut.signal_DB1_Z.value = False
    dut.signal_DB2_I.value = False
    dut.signal_DB3_D.value = False
    dut.signal_DB6_V.value = False
    dut.signal_DB7_N.value = False
    dut.db_bus.value = 0b00000000
    await Timer(1, units="fs")
    dut.enable_P_DB.value = True
    await Timer(1, units="fs")
    assert dut.db_bus.value == 0b1110_1111
    # reset the internal register between tests
    dut.register_data.value = 0b00000000
    await Timer(1, units="fs")

@cocotb.test()
async def test_status_register_alu_flags(dut: SimHandleBase):
    set_signals_low(dut)
    dut.signal_ACR.value = True
    dut.signal_AVR.value = True
    dut.signal_ACR_C.value = True
    dut.signal_AVR_V.value = True
    await Timer(1, units="fs")
    assert dut.register_data.value == 0b0100_0001
    dut.signal_ACR.value = False
    dut.signal_AVR.value = False
    await Timer(1, units="fs")
    assert dut.register_data.value == 0b0000_0000

@cocotb.test()
async def test_bit_5_goes_high_when_enabled(dut: SimHandleBase):
    set_signals_low(dut)
    dut.enable_P_DB.value = True
    await Timer(1, units="fs")
    assert dut.db_bus.value == 0b0010_0000
    dut.enable_P_DB.value = False
    await Timer(1, units="fs")
    assert not dut.db_bus.value.is_resolvable

@cocotb.test()
async def test_status_register_ir5(dut: SimHandleBase):
    set_signals_low(dut)
    dut.signal_IR5.value = True
    dut.signal_IR5_C.value = True
    dut.signal_IR5_I.value = True
    dut.signal_IR5_D.value = True
    await Timer(1, units="fs")
    assert dut.register_data.value == 0b0000_1101
    dut.signal_IR5.value = False
    await Timer(1, units="fs")
    assert dut.register_data.value == 0b0000_0000

def set_signals_low(dut: SimHandleBase):
    dut.signal_DB0_C.value = False
    dut.signal_IR5_C.value = False
    dut.signal_ACR_C.value = False
    dut.signal_DB1_Z.value = False
    dut.signal_DBZ_Z.value = False
    dut.signal_DB2_I.value = False
    dut.signal_IR5_I.value = False
    dut.signal_DB3_D.value = False
    dut.signal_IR5_D.value = False
    dut.signal_DB6_V.value = False
    dut.signal_AVR_V.value = False
    dut.signal_1_V.value = False
    dut.signal_DB7_N.value = False
    dut.signal_IR5.value = False
    dut.signal_ACR.value = False
    dut.signal_AVR.value = False
    dut.enable_P_DB.value = False
    dut.db_bus.value = 0b00000000