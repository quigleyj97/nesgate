from typing import TYPE_CHECKING

import cocotb
from cocotb.triggers import Timer

if TYPE_CHECKING:
    from index_register import IndexRegister as DUT

@cocotb.test()
async def test_index_register(dut: "DUT"):
    # Verify the register can load a value
    dut.data_in.value = 0b00000000
    dut.load.value = False
    await Timer(1, unit="fs")
    dut.load.value = True
    await Timer(1, unit="fs")
    dut.load.value = False
    await Timer(1, unit="fs")
    assert dut.register_data.value == 0b00000000

    # Assert that the register outputs open bus when the enable signal is low
    assert not dut.data_out.value.is_resolvable

    dut.output_enable.value = True
    await Timer(1, unit="fs")

    assert dut.data_out.value == 0b00000000
