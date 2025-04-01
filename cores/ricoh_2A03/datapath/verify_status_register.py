import cocotb
from cocotb.handle import SimHandleBase
from cocotb.triggers import Timer

@cocotb.test()
# Definition for the device under test:
# port(
#     --! @ref Ricoh_2A03_DB
#     db_bus: inout std_ulogic_vector(7 downto 0);
#     --! @ref Ricoh_2A03_Signal_P_DB
#     enable_P_DB: in std_ulogic;
#     --! @ref Ricoh_2A03_Signal_IR5
#     signal_IR5: in std_ulogic;
#     --! @ref Ricoh2A03_ALU_ACR
#     signal_ACR: in std_ulogic;
#     --! @ref Ricoh2A03_ALU_AVR
#     signal_AVR: in std_ulogic;
#     --! @ref Ricoh_Signal_DB0_C
#     signal_DB0_C: in std_ulogic;
#     --! @ref Ricoh_Signal_IR5_C
#     signal_IR5_C: in std_ulogic;
#     --! @ref Ricoh_Signal_ACR_C
#     signal_ACR_C: in std_ulogic;
#     --! @ref Ricoh_Signal_DB1_Z
#     signal_DB1_Z: in std_ulogic;
#     --! @ref Ricoh_Signal_DBZ_Z
#     signal_DBZ_Z: in std_ulogic;
#     --! @ref Ricoh_Signal_DB2_I
#     signal_DB2_I: in std_ulogic;
#     --! @ref Ricoh_Signal_IR5_I
#     signal_IR5_I: in std_ulogic;
#     --! @ref Ricoh_Signal_DB3_D
#     signal_DB3_D: in std_ulogic;
#     --! @ref Ricoh_Signal_IR5_D
#     signal_IR5_D: in std_ulogic;
#     --! @ref Ricoh_Signal_DB6_V
#     signal_DB6_V: in std_ulogic;
#     --! @ref Ricoh_Signal_AVR_V
#     signal_AVR_V: in std_ulogic;
#     --! @ref Ricoh_Signal_1_V
#     signal_1_V: in std_ulogic;
#     --! @ref Ricoh_Signal_DB7_N
#     signal_DB7_N: in std_ulogic
# );
async def test_status_register_data_bus(dut: SimHandleBase):
    # Verify the register can load a value
    dut.db_bus.value = 0b00000000
    dut.enable_P_DB.value = False
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
    await Timer(1, units="fs")
    dut.signal_P_DB.value = True
    await Timer(1, units="fs")
    assert dut.db_bus.value == 0b00100000

@cocotb.test()
async def test_status_register_alu_flags(dut: SimHandleBase):
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
async def test_status_register_ir5(dut: SimHandleBase):
    dut.signal_IR5.value = True
    dut.signal_IR5_C.value = True
    dut.signal_IR5_I.value = True
    dut.signal_IR5_D.value = True
    await Timer(1, units="fs")
    assert dut.register_data.value == 0b0000_0111
    dut.signal_IR5.value = False
    await Timer(1, units="fs")
    assert dut.register_data.value == 0b0000_0000
