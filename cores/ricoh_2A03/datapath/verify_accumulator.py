from typing import TYPE_CHECKING

import cocotb
from cocotb.handle import Release
from cocotb.triggers import Timer

if TYPE_CHECKING:
    from accumulator import Accumulator as DUT

@cocotb.test()
async def test_accumulator_register(dut: "DUT"):
    # Verify the register can load a value
    dut.databus_SB.value = 0b00000000
    dut.load_SB_AC.value = False
    await Timer(1, unit="fs")
    dut.load_SB_AC.value = True
    await Timer(1, unit="fs")
    dut.load_SB_AC.value = False
    await Timer(1, unit="fs")
    assert dut.register_data.value == 0b00000000
    assert dut.databus_DB.value.is_resolvable == False
    dut.databus_SB.value = Release()
    dut.output_enable_AC_DB.value = True
    await Timer(1, unit="fs")
    assert dut.databus_DB.value == 0b00000000
    dut.output_enable_AC_DB.value = False
    dut.output_enable_AC_SB.value = True
    await Timer(1, unit="fs")
    assert dut.databus_SB.value == 0b00000000
