import cocotb
from cocotb.triggers import Timer
from cocotb.handle import SimHandleBase

@cocotb.test()
async def test_data_output_latch(dut: SimHandleBase):
    # Verify the latch can load a value
    dut.data_in.value = 0b00000000
    dut.phi1.value = False
    await Timer(1, units="fs")
    dut.phi1.value = True
    await Timer(1, units="fs")
    dut.phi1.value = False
    await Timer(1, units="fs")
    assert dut.register_data.value == 0b00000000
    # Assert that the latch outputs open bus when the enable signal is low
    assert not dut.data_out.value.is_resolvable

    dut.phi2.value = True
    await Timer(1, units="fs")
    assert dut.data_out.value == 0b00000000
    dut.phi2.value = False
    await Timer(1, units="fs")
