import cocotb
from cocotb.handle import SimHandleBase
from cocotb.triggers import Timer

@cocotb.test()
async def verify_a_input_register(dut: SimHandleBase):
    # Verify the register can load a value
    dut.data_in_SB.value = 0b11111111
    dut.load_SB_ADD.value = True
    dut.clear_0_ADD.value = False
    dut.phi2.value = False
    await Timer(1, units="fs")
    dut.load_SB_ADD.value = True
    dut.phi2.value = True
    await Timer(1, units="fs")
    assert dut.data_out.value == 0b11111111

    dut.phi2.value = False
    await Timer(1, units="fs")
    dut.phi2.value = True

    # Assert that the register can be cleared
    dut.load_SB_ADD.value = False
    dut.clear_0_ADD.value = True
    await Timer(1, units="fs")
    dut.phi2.value = False
    await Timer(1, units="fs")
    assert dut.data_out.value == 0b00000000