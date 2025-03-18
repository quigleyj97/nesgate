import cocotb
from cocotb.handle import SimHandleBase
from cocotb.triggers import Timer

@cocotb.test
async def verify_alu_can_handle_1_and_1(dut: SimHandleBase):
    dut.a.value = 0b00000001
    dut.b.value = 0b00000001
    dut.enable_sum_SUMS.value = True
    dut.enable_xor_EORS.value = False
    dut.enable_and_ANDS.value = False
    dut.enable_or_ORS.value = False
    dut.enable_right_shift_SRS.value = False

    await Timer(1, units='fs')

    assert dut.result.value == 0b00000010, "ALU failed to add 1 + 1"
    assert dut.carry_out_ACR.value == False, "ALU carry out is incorrect"
    assert dut.overflow_AVR.value == False, "ALU overflow is incorrect"
    assert dut.half_carry_HC.value == False, "ALU half carry is incorrect"

    dut.enable_sum_SUMS.value = False
    dut.enable_and_ANDS.value = True

    await Timer(1, units='fs')

    assert dut.result.value == 0b00000001, "ALU failed to AND 1 and 1"
    assert dut.carry_out_ACR.value == False, "ALU carry out is incorrect"
    assert dut.overflow_AVR.value == False, "ALU overflow is incorrect"
    assert dut.half_carry_HC.value == False, "ALU half carry is incorrect"

    dut.enable_and_ANDS.value = False
    dut.enable_xor_EORS.value = True

    await Timer(1, units='fs')

    assert dut.result.value == 0b00000000, "ALU failed to XOR 1 and 1"
    assert dut.carry_out_ACR.value == False, "ALU carry out is incorrect"
    assert dut.overflow_AVR.value == False, "ALU overflow is incorrect"
    assert dut.half_carry_HC.value == False, "ALU half carry is incorrect"

    dut.enable_xor_EORS.value = False
    dut.enable_or_ORS.value = True

    await Timer(1, units='fs')

    assert dut.result.value == 0b00000001, "ALU failed to shift left 1"
    assert dut.carry_out_ACR.value == False, "ALU carry out is incorrect"
    assert dut.overflow_AVR.value == False, "ALU overflow is incorrect"
    assert dut.half_carry_HC.value == False, "ALU half carry is incorrect"

    dut.enable_or_ORS.value = False
    dut.enable_right_shift_SRS.value = True

    await Timer(1, units='fs')

    assert dut.result.value == 0b00000000, "ALU failed to shift right 1"
    assert dut.carry_out_ACR.value == False, "ALU carry out is incorrect"
    assert dut.overflow_AVR.value == False, "ALU overflow is incorrect"
    assert dut.half_carry_HC.value == False, "ALU half carry is incorrect"

@cocotb.test
async def verify_alu_carry_in(dut: SimHandleBase):
    dut.a.value = 0b00000001
    dut.b.value = 0b00000001
    dut.carry_in_IADDC.value = True
    dut.enable_sum_SUMS.value = True
    dut.enable_xor_EORS.value = False
    dut.enable_and_ANDS.value = False
    dut.enable_or_ORS.value = False
    dut.enable_right_shift_SRS.value = False

    await Timer(1, units='fs')

    assert dut.result.value == 0b00000011, "ALU failed to add 1 + 1 + C"

@cocotb.test
async def verify_alu_carry_out(dut: SimHandleBase):
    dut.a.value = 0b11111111
    dut.b.value = 0b00000010
    dut.carry_in_IADDC.value = False
    dut.enable_sum_SUMS.value = True
    dut.enable_xor_EORS.value = False
    dut.enable_and_ANDS.value = False
    dut.enable_or_ORS.value = False
    dut.enable_right_shift_SRS.value = False

    await Timer(1, units='fs')

    assert dut.result.value == 0b00000001, "ALU failed to add 255 + 1"
    assert dut.carry_out_ACR.value == True, "ALU failed to set carry out bit"

@cocotb.test
async def verify_alu_overflow(dut: SimHandleBase):
    dut.a.value = 0x7F
    dut.b.value = 0x01
    dut.carry_in_IADDC.value = False
    dut.enable_sum_SUMS.value = True
    dut.enable_xor_EORS.value = False
    dut.enable_and_ANDS.value = False
    dut.enable_or_ORS.value = False
    dut.enable_right_shift_SRS.value = False

    await Timer(1, units='fs')

    assert dut.result.value == 0x80, "ALU failed to add 255 + 1"
    assert dut.overflow_AVR.value == True, "ALU failed to set overflow bit"
