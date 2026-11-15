from typing import TYPE_CHECKING

import cocotb
from cocotb.triggers import Timer

if TYPE_CHECKING:
    from a_input_register import AInputRegister as DUT

@cocotb.test()
async def verify_a_input_register(dut: "DUT"):
    # Verify the register can load a value
    dut.data_in_SB.value = 0b11111111
    dut.load_SB_ADD.value = True
    dut.clear_0_ADD.value = False
    dut.metaclock.value = False
    await Timer(1, unit="fs")
    dut.load_SB_ADD.value = True
    dut.metaclock.value = True
    await Timer(1, unit="fs")
    assert dut.data_out.value == 0b11111111

    dut.metaclock.value = False
    await Timer(1, unit="fs")
    dut.metaclock.value = True

    # Assert that the register can be cleared
    dut.load_SB_ADD.value = False
    dut.clear_0_ADD.value = True
    await Timer(1, unit="fs")
    dut.metaclock.value = False
    await Timer(1, unit="fs")
    assert dut.data_out.value == 0b00000000