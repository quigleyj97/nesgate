import cocotb
from cocotb.triggers import Timer
from cocotb.handle import SimHandleBase

@cocotb.test()
async def test_adder_hold_register(dut: SimHandleBase):
    # Verify the register can load a value
    dut.data_in.value = 0b00000000
    dut.load.value = False
    await Timer(1, units="fs")
    dut.load.value = True
    await Timer(1, units="fs")
    dut.load.value = False
    await Timer(1, units="fs")
    assert dut.register_data.value == 0b00000000

    # Assert that the register outputs open bus when the enable signal is low
    assert not dut.sb_bus_port.value.is_resolvable
    assert not dut.adh_bus_port.value.is_resolvable

    dut.adh_bus_enable_ADD_ADL.value = True
    dut.sb_bus_enable_ADD_SB.value = True
    await Timer(1, units="fs")

    assert dut.sb_bus_port.value == 0b00000000
    assert dut.adh_bus_port.value == 0b00000000
    
