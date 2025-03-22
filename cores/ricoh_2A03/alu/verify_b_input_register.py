import cocotb
from cocotb.handle import SimHandleBase
from cocotb.triggers import Timer
from cocotb.clock import Clock

@cocotb.test()
async def verify_b_input_register(dut: SimHandleBase):
    clk = Clock(dut.metaclock, 2, units="fs")
    await cocotb.start(clk.start())
    dut.control_db_add.value = 1
    dut.control_adl_add.value = 0
    dut.control_not_db_add.value = 0
    dut.data_in_db.value = 0b10101010
    await Timer(10, units="fs")
    assert dut.data_out.value == 0b10101010, f"Expected 0b10101010, got {dut.data_out.value}"

    dut.control_db_add.value = 0
    dut.control_adl_add.value = 1
    dut.control_not_db_add.value = 0
    dut.data_in_adl.value = 0b11001100
    await Timer(10, units="fs")
    assert dut.data_out.value == 0b11001100, f"Expected 0b11001100, got {dut.data_out.value}"

    dut.control_db_add.value = 0
    dut.control_adl_add.value = 0
    dut.control_not_db_add.value = 1
    dut.data_in_db.value = 0b11110000
    await Timer(10, units="fs")
    assert dut.data_out.value == 0b00001111, f"Expected 0b00001111, got {dut.data_out.value}"