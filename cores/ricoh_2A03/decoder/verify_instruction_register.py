from typing import TYPE_CHECKING

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

if TYPE_CHECKING:
    from instruction_register import InstructionRegister as DUT


@cocotb.test()
async def test_instruction_register(dut: "DUT"):
    """The register loads during Phi1 while FETCH is asserted and holds otherwise"""

    cocotb.start_soon(Clock(dut.metaclock, 1, unit="ns").start())

    dut.phi1.value = 0
    dut.load_opcode_FETCH.value = 0
    dut.predecode_in.value = 0xA9
    await ClockCycles(dut.metaclock, 2)
    assert dut.instruction_out.value == 0x00, "Loaded without Phi1 or FETCH"

    # FETCH alone isn't enough
    dut.load_opcode_FETCH.value = 1
    await ClockCycles(dut.metaclock, 2)
    assert dut.instruction_out.value == 0x00, "Loaded outside of Phi1"

    # Neither is Phi1 alone
    dut.load_opcode_FETCH.value = 0
    dut.phi1.value = 1
    await ClockCycles(dut.metaclock, 2)
    assert dut.instruction_out.value == 0x00, "Loaded without FETCH"

    # Follows the predecoded opcode during Phi1 while FETCH is asserted
    dut.load_opcode_FETCH.value = 1
    await ClockCycles(dut.metaclock, 2)
    assert dut.instruction_out.value == 0xA9, "Did not load during Phi1 and FETCH"
    dut.predecode_in.value = 0xEA
    await ClockCycles(dut.metaclock, 2)
    assert dut.instruction_out.value == 0xEA, "Did not follow the opcode during Phi1"

    # Holds once Phi1 falls, through Phi2, even with FETCH still high
    dut.phi1.value = 0
    await ClockCycles(dut.metaclock, 1)
    dut.predecode_in.value = 0x00
    await ClockCycles(dut.metaclock, 2)
    assert dut.instruction_out.value == 0xEA, "Did not hold its value after Phi1"

    # Holds through the next Phi1 when FETCH is deasserted, e.g. mid-instruction
    dut.load_opcode_FETCH.value = 0
    dut.phi1.value = 1
    await ClockCycles(dut.metaclock, 2)
    assert dut.instruction_out.value == 0xEA, "Did not hold its value without FETCH"
