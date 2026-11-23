from typing import TYPE_CHECKING

import cocotb
from cocotb.triggers import Timer

if TYPE_CHECKING:
    from decoder_rom import DecoderRom as DUT

CYCLES = {
    "T0": "cycle_T0",
    "T1X": "cycle_T1X",
    "T2": "cycle_T2",
    "T3": "cycle_T3",
    "T4": "cycle_T4",
    "T5": "cycle_T5",
}

# Every decoder line: its number, the opcodes it matches (MSB first, X for
# don't care), and the cycle it fires in (TX for any). These are the decoded
# masks from the decoder table, not the raw bits the VHDL uses, so the two check
# each other. Line 128 also checks IR0, which the table's raw bits leave out.
LINES = [
    (0, "100XX100", "TX", "STY"),
    (1, "XXX100X1", "T3", "OP ind, Y"),
    (2, "XXX110X1", "T2", "OP abs, Y"),
    (3, "1X001000", "T0", "DEY INY"),
    (4, "10011000", "T0", "TYA"),
    (5, "1100XX00", "T0", "CPY INY"),
    (6, "XXX1X1XX", "T2", "OP zpg, X/Y & OP abs, X/Y"),
    (7, "10XXXX1X", "TX", "LDX STX A>X S>X"),
    (8, "XXX000X1", "T2", "OP ind, X"),
    (9, "1000101X", "T0", "TXA"),
    (10, "1100101X", "T0", "DEX"),
    (11, "1110XX00", "T0", "CPX INX"),
    (12, "100XXX1X", "TX", "STX TXA TXS"),
    (13, "1001101X", "T0", "TXS"),
    (14, "101XXX1X", "T0", "LDX TAX TSX"),
    (15, "1100101X", "T1X", "DEX"),
    (16, "11101000", "T1X", "INX"),
    (17, "1011101X", "T0", "TSX"),
    (18, "1X001000", "T1X", "DEY INY"),
    (19, "101XX100", "T0", "LDY"),
    (20, "1010XX00", "T0", "LDY TAY"),
    (21, "00100000", "T0", "JSR"),
    (22, "00000000", "T5", "BRK"),
    (23, "0X001000", "T0", "Push"),
    (24, "01100000", "T4", "RTS"),
    (25, "0X101000", "T3", "Pull"),
    (26, "01000000", "T5", "RTI"),
    (27, "011XXX1X", "TX", "ROR"),
    (28, "XXXXXXXX", "T2", "T2 ANY"),
    (29, "010XXXX1", "T0", "EOR"),
    (30, "01X01100", "TX", "JMP (excluder for C11)"),
    (31, "XXX011XX", "T2", "ALU absolute"),
    (32, "000XXXX1", "T0", "ORA"),
    (33, "XXXX0XXX", "T2", "Left half (X0-X7)"),
    (34, "XXXXXXXX", "T0", "T0 ANY"),
    (35, "0XX0X000", "T2", "BRK JSR RTI RTS Push/pull"),
    (36, "0XX0XX00", "T3", "BRK JSR RTI RTS Push/pull BIT JMP"),
    (37, "00X00000", "T4", "BRK JSR"),
    (38, "01000000", "T4", "RTI"),
    (39, "XXX000X1", "T3", "OP X, ind"),
    (40, "XXX100X1", "T4", "OP ind, Y"),
    (41, "XXX100X1", "T2", "OP ind, Y"),
    (42, "XXX11XXX", "T3", "RIGHT ODD"),
    (43, "0X101000", "TX", "Pull"),
    (44, "111XXX1X", "TX", "INC NOP"),
    (45, "XXX000X1", "T4", "OP X, ind"),
    (46, "XXX100X1", "T3", "OP ind, Y"),
    (47, "01X00000", "TX", "RTI RTS"),
    (48, "00100000", "T2", "JSR"),
    (49, "11X0XX00", "T0", "CPY CPX INY INX"),
    (50, "110XXXX1", "T0", "CMP"),
    (51, "111XXXX1", "T0", "SBC"),
    (52, "X11XXXX1", "T0", "ADC SBC"),
    (53, "001XXX1X", "TX", "ROL"),
    (54, "01X01100", "T3", "JMP ind"),
    (55, "00XXXX1X", "TX", "ASL ROL"),
    (56, "00100000", "T5", "JSR"),
    (57, "0XX0X000", "T2", "BRK JSR RTI RTS Push/pull"),
    (58, "10011000", "T0", "TYA"),
    (59, "0XXXXXX1", "T1X", "UPPER ODD"),
    (60, "X11XXXX1", "T1X", "ADC SBC"),
    (61, "0XX0101X", "T1X", "ASL ROL LSR ROR"),
    (62, "1000101X", "T0", "TXA"),
    (63, "01101000", "T0", "PLA"),
    (64, "101XXXX1", "T0", "LDA"),
    (65, "XXXXXXX1", "T0", "ALL ODD"),
    (66, "10101000", "T0", "TAY"),
    (67, "0XX0101X", "T0", "ASL ROL LSR ROR"),
    (68, "1010101X", "T0", "TAX"),
    (69, "0010X100", "T0", "BIT0"),
    (70, "001XXXX1", "T0", "AND0"),
    (71, "XXX11XXX", "T4", "OP abs,XY"),
    (72, "XXX100X1", "T5", "OP ind,Y"),
    (73, "XXX10000", "T0", "Branch T0"),
    (74, "01001000", "T2", "PHA"),
    (75, "01X0101X", "T0", "LSR ROR"),
    (76, "01XXXX1X", "TX", "LSR ROR"),
    (77, "00000000", "T2", "BRK"),
    (78, "00100000", "T3", "JSR"),
    (79, "100XXXX1", "TX", "STA"),
    (80, "XXX10000", "T2", "BR2 (Branch T2)"),
    (81, "XXXX01XX", "T2", "zero page"),
    (82, "XXXX00X1", "T2", "ALU indirect"),
    (83, "XXXX1XXX", "T2", "Right half (X8-XF)"),
    (84, "01100000", "T5", "RTS"),
    (85, "XXXXXXXX", "T4", "T4 ANY"),
    (86, "XXXXXXXX", "T3", "T3 ANY"),
    (87, "0X000000", "T0", "BRK RTI"),
    (88, "01X01100", "T0", "JMP"),
    (89, "XXX000X1", "T5", "OP X, ind"),
    (90, "XXXX1XXX", "T3", "Right half (X8-XF)"),
    (91, "XXX100X1", "T4", "OP ind, Y"),
    (92, "XXX11XXX", "T3", "RIGHT ODD"),
    (93, "XXX10000", "T3", "BR3 (Branch T3)"),
    (94, "0X000000", "TX", "BRK RTI"),
    (95, "00100000", "TX", "JSR"),
    (96, "01X01100", "TX", "JMP"),
    (97, "100XXXXX", "TX", "STORE"),
    (98, "00000000", "T4", "BRK"),
    (99, "00001000", "T2", "PHP"),
    (100, "0X001000", "T2", "Push"),
    (101, "01X01100", "T4", "JMP ind"),
    (102, "01X00000", "T5", "RTI RTS"),
    (103, "00100000", "T5", "JSR"),
    (104, "01001100", "T2", "JMP abs"),
    (105, "0X101000", "T3", "Pull"),
    (106, "X1XXXX1X", "TX", "LSR ROR DEC INC DEX NOP"),
    (107, "00XXXX1X", "TX", "ASL ROL"),
    (108, "01X11000", "T0", "CLI SEI"),
    (109, "0010X100", "T1X", "BIT"),
    (110, "00X11000", "T0", "CLC SEC"),
    (111, "XXX101XX", "T3", "Memory zero page X/Y"),
    (112, "X11XXXX1", "T1X", "ADC SBC"),
    (113, "0010X100", "T0", "BIT"),
    (114, "00101000", "T0", "PLP"),
    (115, "01000000", "T4", "RTI"),
    (116, "110XXXX1", "T1X", "CMP"),
    (117, "11X01100", "T1X", "CPY CPX abs"),
    (118, "00X0101X", "T1X", "ASL ROL"),
    (119, "11X00X00", "T1X", "CPY CPX zpg/immed"),
    (120, "11X11000", "T0", "CLD SED"),
    (121, "X0XXXXXX", "TX", "/IR6"),
    (122, "XXX011XX", "T3", "Memory absolute"),
    (123, "XXX001XX", "T2", "Memory zero page"),
    (124, "XXXX00X1", "T5", "Memory indirect"),
    (125, "XXX11XXX", "T4", "Memory absolute X/Y"),
    (126, "0XXXXXXX", "TX", "/IR7"),
    (127, "10111000", "TX", "CLV"),
    (128, "XXXX10X0", "TX", "IMPL"),
    (129, "0XX01000", "TX", "Push/pull"),
]

PUSH_PULL = 129
EXCLUDES_PUSH_PULL = {83, 90, 128}
BRANCH_T0 = 73


def matches(mask: str, opcode: int) -> bool:
    """Whether the opcode matches a decoded mask like `XXX100X1`"""
    return all(
        bit == "X" or int(bit) == (opcode >> (7 - i)) & 1 for i, bit in enumerate(mask)
    )


def expected(opcode: int, cycles: set[str], prdy: int = 1) -> set[int]:
    """The decoder lines a real 6502 asserts, including the in-situ extra logic"""
    result = {
        n
        for n, mask, cycle, _ in LINES
        if matches(mask, opcode) and (cycle == "TX" or cycle in cycles)
    }
    if PUSH_PULL in result:
        result -= EXCLUDES_PUSH_PULL
    if not prdy:
        result.discard(BRANCH_T0)
    return result


def describe(lines: set[int]) -> list[str]:
    return [f"{n} ({LINES[n][3]})" for n in sorted(lines)]


async def decode(dut: "DUT", opcode: int, cycles: set[str], prdy: int = 1) -> set[int]:
    """Drive the inputs and return the asserted decoder lines"""
    dut.instruction_in.value = opcode
    for name, port in CYCLES.items():
        getattr(dut, port).value = int(name in cycles)
    dut.previous_ready_PRDY.value = prdy
    await Timer(1, unit="ns")
    value = dut.decoder_out.value.to_unsigned()
    return {n for n in range(len(LINES)) if value >> n & 1}


async def check(dut: "DUT", opcode: int, cycles: set[str], prdy: int = 1):
    actual = await decode(dut, opcode, cycles, prdy)
    want = expected(opcode, cycles, prdy)
    assert actual == want, (
        f"Opcode {opcode:#04x} during {sorted(cycles)} (PRDY={prdy}): "
        f"missing {describe(want - actual)}, extra {describe(actual - want)}"
    )


@cocotb.test()
async def test_line_table(dut: "DUT"):
    """The reference table lists every line in order"""
    assert [n for n, *_ in LINES] == list(range(130))
    assert len(dut.decoder_out.value) == len(LINES)


@cocotb.test()
async def test_every_opcode_and_cycle(dut: "DUT"):
    """Every opcode decodes to the right lines in every cycle, and outside them"""
    for cycles in [set(), *({name} for name in CYCLES)]:
        for opcode in range(256):
            await check(dut, opcode, cycles)


@cocotb.test()
async def test_overlapping_cycles(dut: "DUT"):
    """T0 and T2 overlap on 2-cycle instructions, so both sets of lines fire"""
    for opcode in range(256):
        await check(dut, opcode, {"T0", "T2"})
        await check(dut, opcode, {"T1X", "T2"})


@cocotb.test()
async def test_examples(dut: "DUT"):
    lda_immediate = await decode(dut, 0xA9, {"T0"})
    assert {34, 64, 65} <= lda_immediate, "LDA # at T0: T0 ANY, LDA, ALL ODD"

    assert 22 in await decode(dut, 0x00, {"T5"}), "BRK5"
    assert 22 not in await decode(dut, 0x00, {"T4"}), "BRK5 outside T5"
    assert 48 in await decode(dut, 0x20, {"T2"}), "JSR2"
    assert 74 in await decode(dut, 0x48, {"T2"}), "PHA at T2"
    assert 10 in await decode(dut, 0xCA, {"T0"}), "DEX at T0"
    assert 15 in await decode(dut, 0xCA, {"T1X"}), "DEX at T1"
    assert 126 in await decode(dut, 0x10, set()), "/IR7 for BPL"
    assert 126 not in await decode(dut, 0x90, set()), "/IR7 for BCC"


@cocotb.test()
async def test_push_pull_exclusion(dut: "DUT"):
    """Lines 83, 90 and 128 don't fire for the stack push/pull instructions"""
    for opcode in (0x08, 0x28, 0x48, 0x68):  # PHP PLP PHA PLA
        assert PUSH_PULL in await decode(dut, opcode, set())
        assert 83 not in await decode(dut, opcode, {"T2"}), f"ABS/2 for {opcode:#04x}"
        assert 90 not in await decode(dut, opcode, {"T3"}), f"Line 90 for {opcode:#04x}"
        assert 128 not in await decode(dut, opcode, set()), f"IMPL for {opcode:#04x}"

    assert 83 in await decode(dut, 0x0D, {"T2"}), "ABS/2 for ORA abs"
    assert 90 in await decode(dut, 0x0D, {"T3"}), "Line 90 for ORA abs"
    for opcode in (0x0A, 0x18, 0xAA, 0xEA):  # ASL A, CLC, TAX, NOP
        assert 128 in await decode(dut, opcode, set()), f"IMPL for {opcode:#04x}"


@cocotb.test()
async def test_impl_checks_ir0(dut: "DUT"):
    """IMPL needs IR0 = 0, so immediate ALU instructions (XXXX10X1) don't match"""
    for opcode in (0x09, 0x29, 0x49, 0x69, 0xA9, 0xC9, 0xE9):
        assert 128 not in await decode(dut, opcode, set()), f"IMPL for {opcode:#04x}"


@cocotb.test()
async def test_branch_t0_prdy(dut: "DUT"):
    """Branch T0 only fires if the CPU was ready on the previous cycle"""
    for opcode in range(0x10, 0x100, 0x20):
        assert BRANCH_T0 in await decode(dut, opcode, {"T0"}, prdy=1)
        assert BRANCH_T0 not in await decode(dut, opcode, {"T0"}, prdy=0)
    # PRDY affects no other line
    for opcode in range(256):
        for cycles in [set(), *({name} for name in CYCLES)]:
            await check(dut, opcode, cycles, prdy=0)
