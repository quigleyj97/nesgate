from typing import TYPE_CHECKING

import cocotb
from cocotb.triggers import Timer

if TYPE_CHECKING:
    from predecode_logic import PredecodeLogic as DUT

# The 151 documented 6502 opcodes
DOCUMENTED_OPCODES = {
    0x00, 0x01, 0x05, 0x06, 0x08, 0x09, 0x0A, 0x0D, 0x0E,
    0x10, 0x11, 0x15, 0x16, 0x18, 0x19, 0x1D, 0x1E,
    0x20, 0x21, 0x24, 0x25, 0x26, 0x28, 0x29, 0x2A, 0x2C, 0x2D, 0x2E,
    0x30, 0x31, 0x35, 0x36, 0x38, 0x39, 0x3D, 0x3E,
    0x40, 0x41, 0x45, 0x46, 0x48, 0x49, 0x4A, 0x4C, 0x4D, 0x4E,
    0x50, 0x51, 0x55, 0x56, 0x58, 0x59, 0x5D, 0x5E,
    0x60, 0x61, 0x65, 0x66, 0x68, 0x69, 0x6A, 0x6C, 0x6D, 0x6E,
    0x70, 0x71, 0x75, 0x76, 0x78, 0x79, 0x7D, 0x7E,
    0x81, 0x84, 0x85, 0x86, 0x88, 0x8A, 0x8C, 0x8D, 0x8E,
    0x90, 0x91, 0x94, 0x95, 0x96, 0x98, 0x99, 0x9A, 0x9D,
    0xA0, 0xA1, 0xA2, 0xA4, 0xA5, 0xA6, 0xA8, 0xA9, 0xAA, 0xAC, 0xAD, 0xAE,
    0xB0, 0xB1, 0xB4, 0xB5, 0xB6, 0xB8, 0xB9, 0xBA, 0xBC, 0xBD, 0xBE,
    0xC0, 0xC1, 0xC4, 0xC5, 0xC6, 0xC8, 0xC9, 0xCA, 0xCC, 0xCD, 0xCE,
    0xD0, 0xD1, 0xD5, 0xD6, 0xD8, 0xD9, 0xDD, 0xDE,
    0xE0, 0xE1, 0xE4, 0xE5, 0xE6, 0xE8, 0xE9, 0xEA, 0xEC, 0xED, 0xEE,
    0xF0, 0xF1, 0xF5, 0xF6, 0xF8, 0xF9, 0xFD, 0xFE,
}

# Documented opcodes that always take 2 cycles. Branches take 2 cycles only
# when not taken, and have an operand, so they aren't TWOCYCLE.
TWO_CYCLE_OPCODES = {
    # Immediate operand: ORA AND EOR ADC LDA CMP SBC, LDY LDX CPY CPX
    0x09, 0x29, 0x49, 0x69, 0xA9, 0xC9, 0xE9, 0xA0, 0xA2, 0xC0, 0xE0,
    # Flags: CLC SEC CLI SEI CLV CLD SED
    0x18, 0x38, 0x58, 0x78, 0xB8, 0xD8, 0xF8,
    # Transfers: TAX TXA TAY TYA TSX TXS
    0xAA, 0x8A, 0xA8, 0x98, 0xBA, 0x9A,
    # INX INY DEX DEY NOP
    0xE8, 0xC8, 0xCA, 0x88, 0xEA,
    # Accumulator: ASL ROL LSR ROR
    0x0A, 0x2A, 0x4A, 0x6A,
}

# Documented single-byte opcodes the predecode logic flags as IMPLIED. BRK, RTI
# and RTS are also a single byte, but the PC increment logic handles them
# separately, so they aren't flagged.
IMPLIED_OPCODES = {
    0x08, 0x18, 0x28, 0x38, 0x48, 0x58, 0x68, 0x78,
    0x88, 0x98, 0xA8, 0xB8, 0xC8, 0xD8, 0xE8, 0xF8,
    0x0A, 0x2A, 0x4A, 0x6A, 0x8A, 0x9A, 0xAA, 0xBA, 0xCA, 0xEA,
}

def nor(*inputs: bool) -> bool:
    return not any(inputs)

def reference_predecode(opcode: int) -> tuple[bool, bool]:
    pd = [bool(opcode >> i & 1) for i in range(8)]
    n_pd = [not b for b in pd]
    implied = nor(pd[0], pd[2], n_pd[3])
    tmp1 = nor(pd[1], pd[4], pd[7])
    tmp2 = nor(n_pd[0], pd[2], n_pd[3], pd[4])
    tmp3 = nor(pd[0], pd[2], pd[3], pd[4], n_pd[7])
    two_cycle = (implied and not tmp1) or tmp2 or tmp3
    return two_cycle, implied

async def apply(dut: "DUT", opcode: int, inject_brk: bool) -> None:
    dut.predecode_in.value = opcode
    dut.inject_brk_0_IR.value = inject_brk
    await Timer(1, unit="ns")

@cocotb.test()
async def test_matches_reference_netlist(dut: "DUT"):
    for opcode in range(256):
        await apply(dut, opcode, False)
        two_cycle, implied = reference_predecode(opcode)
        assert dut.predecode_out.value == opcode, f"opcode {opcode:#04x} not passed through"
        assert bool(dut.short_instruction_TWOCYCLE.value) == two_cycle, f"TWOCYCLE wrong for {opcode:#04x}"
        assert bool(dut.single_byte_IMPLIED.value) == implied, f"IMPLIED wrong for {opcode:#04x}"

@cocotb.test()
async def test_documented_opcodes(dut: "DUT"):
    """Documented opcodes are classified by their known cycle counts and lengths"""
    assert len(DOCUMENTED_OPCODES) == 151
    for opcode in sorted(DOCUMENTED_OPCODES):
        await apply(dut, opcode, False)
        assert bool(dut.short_instruction_TWOCYCLE.value) == (opcode in TWO_CYCLE_OPCODES), \
            f"TWOCYCLE wrong for {opcode:#04x}"
        assert bool(dut.single_byte_IMPLIED.value) == (opcode in IMPLIED_OPCODES), \
            f"IMPLIED wrong for {opcode:#04x}"

@cocotb.test()
async def test_inject_brk(dut: "DUT"):
    """0/IR forces the opcode to BRK and clears both outputs"""
    for opcode in range(256):
        await apply(dut, opcode, True)
        assert dut.predecode_out.value == 0x00, f"BRK not injected over {opcode:#04x}"
        assert not dut.short_instruction_TWOCYCLE.value
        assert not dut.single_byte_IMPLIED.value
