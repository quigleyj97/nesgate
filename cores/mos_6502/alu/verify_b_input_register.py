from typing import TYPE_CHECKING

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer

if TYPE_CHECKING:
    from b_input_register import BInputRegister as DUT

@cocotb.test()
async def verify_b_input_register(dut: "DUT"):
    clk = Clock(dut.metaclock, 2, unit="fs")
    cocotb.start_soon(clk.start())
    dut.control_db_add.value = 1
    dut.control_adl_add.value = 0
    dut.control_not_db_add.value = 0
    dut.data_in_db.value = 0b10101010
    await Timer(10, unit="fs")
    assert dut.data_out.value == 0b10101010, f"Expected 0b10101010, got {dut.data_out.value}"

    dut.control_db_add.value = 0
    dut.control_adl_add.value = 1
    dut.control_not_db_add.value = 0
    dut.data_in_adl.value = 0b11001100
    await Timer(10, unit="fs")
    assert dut.data_out.value == 0b11001100, f"Expected 0b11001100, got {dut.data_out.value}"

    dut.control_db_add.value = 0
    dut.control_adl_add.value = 0
    dut.control_not_db_add.value = 1
    dut.data_in_db.value = 0b11110000
    await Timer(10, unit="fs")
    assert dut.data_out.value == 0b00001111, f"Expected 0b00001111, got {dut.data_out.value}"