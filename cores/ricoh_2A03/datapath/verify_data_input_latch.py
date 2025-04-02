import cocotb
from cocotb.triggers import Timer
from cocotb.handle import SimHandleBase

@cocotb.test()
async def test_data_input_latch(dut: SimHandleBase):
    # Verify the register can load a value
    dut.data_in.value = 0b00000000
    dut.load.value = False
    dut.db_bus_enable_DL_DB.value = False
    dut.adh_bus_enable_DL_ADH.value = False
    dut.adl_bus_enable_DL_ADL.value = False
    await Timer(1, units="fs")
    dut.load.value = True
    await Timer(1, units="fs")
    dut.load.value = False
    await Timer(1, units="fs")
    assert dut.register_data.value == 0b00000000

    # Assert that the register outputs open bus when the enable signals are low
    assert not dut.db_bus_port.value.is_resolvable
    assert not dut.adh_bus_port.value.is_resolvable
    assert not dut.adl_bus_port.value.is_resolvable

    dut.db_bus_enable_DL_DB.value = True
    await Timer(1, units="fs")
    assert dut.db_bus_port.value == 0b00000000
    dut.db_bus_enable_DL_DB.value = False

    dut.adh_bus_enable_DL_ADH.value = True
    await Timer(1, units="fs")
    assert dut.adh_bus_port.value == 0b00000000
    assert not dut.db_bus_port.value.is_resolvable
    dut.adh_bus_enable_DL_ADH.value = False

    dut.adl_bus_enable_DL_ADL.value = True
    await Timer(1, units="fs")
    assert dut.adl_bus_port.value == 0b00000000
    assert not dut.adh_bus_port.value.is_resolvable
