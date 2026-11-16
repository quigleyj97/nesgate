from typing import TYPE_CHECKING

import cocotb
from cocotb.triggers import Timer

if TYPE_CHECKING:
    from status_register import StatusRegister as DUT

@cocotb.test()
async def test_status_register_data_bus(dut: "DUT"):
    # Verify the register can load a value
    set_signals_low(dut)
    dut.signal_DB0_C.value = True
    dut.signal_DB1_Z.value = True
    dut.signal_DB2_I.value = True
    dut.signal_DB3_D.value = True
    dut.signal_DB6_V.value = True
    dut.signal_DB7_N.value = True
    await Timer(1, unit="fs")
    assert dut.register_data.value == 0b00000000
    assert dut.DBZ.value == True

    # Test that setting DB to all ones doesn't set every single bit
    dut.db_bus_in.value = 0b11111111
    await Timer(1, unit="fs")
    assert dut.register_data.value == 0b11001111
    assert dut.DBZ.value == False

    # Test bus output
    await Timer(1, unit="fs")
    dut.signal_DB0_C.value = False
    dut.signal_DB1_Z.value = False
    dut.signal_DB2_I.value = False
    dut.signal_DB3_D.value = False
    dut.signal_DB6_V.value = False
    dut.signal_DB7_N.value = False
    dut.db_bus_in.value = 0b00000000
    await Timer(1, unit="fs")
    dut.enable_P_DB.value = True
    await Timer(1, unit="fs")
    assert str(dut.db_bus_out.value) == "111Z1111", "Bit 4 isn't driven"
    # Clear the flags between tests, by loading zeros from DB
    dut.enable_P_DB.value = False
    await clear_flags(dut)

@cocotb.test()
async def test_status_register_alu_flags(dut: "DUT"):
    set_signals_low(dut)
    dut.signal_ACR.value = True
    dut.signal_AVR.value = True
    dut.signal_ACR_C.value = True
    dut.signal_AVR_V.value = True
    await Timer(1, unit="fs")
    assert dut.register_data.value == 0b0100_0001
    dut.signal_ACR.value = False
    dut.signal_AVR.value = False
    await Timer(1, unit="fs")
    assert dut.register_data.value == 0b0000_0000

@cocotb.test()
async def test_bit_5_goes_high_when_enabled(dut: "DUT"):
    set_signals_low(dut)
    dut.enable_P_DB.value = True
    await Timer(1, unit="fs")
    assert str(dut.db_bus_out.value) == "001Z0000", "Bit 4 isn't driven"
    dut.enable_P_DB.value = False
    await Timer(1, unit="fs")
    assert not dut.db_bus_out.value.is_resolvable

@cocotb.test()
async def test_status_register_ir5(dut: "DUT"):
    set_signals_low(dut)
    dut.signal_IR5.value = True
    dut.signal_IR5_C.value = True
    dut.signal_IR5_I.value = True
    dut.signal_IR5_D.value = True
    await Timer(1, unit="fs")
    assert dut.register_data.value == 0b0000_1101
    dut.signal_IR5.value = False
    await Timer(1, unit="fs")
    assert dut.register_data.value == 0b0000_0000

@cocotb.test()
async def test_status_register_dbz(dut: "DUT"):
    """DBZ/Z sets Z only when every bit of DB is zero."""
    set_signals_low(dut)
    dut.signal_DBZ_Z.value = True
    await Timer(1, unit="fs")
    assert dut.DBZ.value == True
    assert dut.register_data.value == 0b0000_0010
    # Any single set bit, including bit 0, means DB isn't zero
    for bit in range(8):
        dut.db_bus_in.value = 1 << bit
        await Timer(1, unit="fs")
        assert dut.DBZ.value == False, f"DBZ high with DB = {1 << bit:#04x}"
        assert dut.register_data.value == 0b0000_0000
    for value in [0x7F, 0xFE, 0xFF]:
        dut.db_bus_in.value = value
        await Timer(1, unit="fs")
        assert dut.DBZ.value == False, f"DBZ high with DB = {value:#04x}"
    dut.signal_DBZ_Z.value = False
    await Timer(1, unit="fs")

def set_signals_low(dut: "DUT"):
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
    dut.db_bus_in.value = 0b00000000


async def clear_flags(dut: "DUT"):
    """Load every flag from DB while DB is zero."""
    dut.db_bus_in.value = 0
    for name in ["signal_DB0_C", "signal_DB1_Z", "signal_DB2_I", "signal_DB3_D", "signal_DB6_V", "signal_DB7_N"]:
        getattr(dut, name).value = True
    await Timer(1, unit="fs")
    for name in ["signal_DB0_C", "signal_DB1_Z", "signal_DB2_I", "signal_DB3_D", "signal_DB6_V", "signal_DB7_N"]:
        getattr(dut, name).value = False
    await Timer(1, unit="fs")
    assert dut.register_data.value == 0
