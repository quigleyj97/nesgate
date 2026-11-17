"""End-to-end tests of the whole CPU, running programs from memory.

Each test loads a small program, resets the CPU into it, and checks what it
does on the bus: either the exact sequence of bus cycles, which pins down the
cycle timing of each instruction, or just the values it stores to memory.

Every test in this module runs in the same simulation, so each one starts with
the CPU wherever the last test left it, and relies on reset to recover.
"""

from typing import TYPE_CHECKING

import cocotb

from cores.ricoh_2A03.harness import (
    IRQ_VECTOR,
    NMI_VECTOR,
    RESET_VECTOR,
    Mos6502Harness,
    assert_trace,
    fetch,
    read,
    write,
)

if TYPE_CHECKING:
    from mos_6502 import Mos6502 as DUT

#: Where every test program starts
ORIGIN = 0x8000
#: Where the test programs store their results
RESULTS = 0x0200


async def boot(dut: "DUT", program: list[int], origin: int = ORIGIN) -> Mos6502Harness:
    """Load a program, and reset the CPU up to its first opcode fetch."""
    cpu = Mos6502Harness(dut)
    cpu.load(origin, program)
    cpu.set_vector(RESET_VECTOR, origin)
    await cpu.start()
    await cpu.reset()
    return cpu


def jmp_self(address: int) -> list[int]:
    """`JMP address`, placed at `address`: an infinite loop to end a program."""
    return [0x4C, address & 0xFF, address >> 8]


async def run_to_end(cpu: Mos6502Harness, end: int, max_cycles: int = 1000):
    """Run until the program reaches its final `JMP *` at `end`."""
    await cpu.run_until_fetch(end, max_cycles)


def results(cpu: Mos6502Harness, count: int) -> list[int]:
    return list(cpu.memory[RESULTS : RESULTS + count])


# region Reset


@cocotb.test()
async def test_reset_sequence(dut: "DUT"):
    """Reset runs the BRK sequence with the pushes turned into reads, then
    fetches the reset vector and jumps to it. S ends up 3 lower, as if the
    pushes had happened, and I is set."""
    cpu = Mos6502Harness(dut)
    cpu.load(ORIGIN, [
        0xBA,               # 8000 TSX
        0x8E, 0x00, 0x02,   # 8001 STX $0200
        0x08,               # 8004 PHP
        0x68,               # 8005 PLA
        0x8D, 0x01, 0x02,   # 8006 STA $0201
        *jmp_self(0x8009),  # 8009 JMP *
    ])
    cpu.set_vector(RESET_VECTOR, ORIGIN)
    await cpu.start()
    sequence = await cpu.reset()

    assert all(c.read for c in sequence), "Wrote to memory during reset"
    # The last five cycles are the three suppressed stack pushes and the
    # vector fetch. Where the stack pointer was before reset depends on what
    # the CPU was doing, so only check that the pushes walk down page 1.
    pushes, vector = sequence[-5:-2], sequence[-2:]
    assert [c.address >> 8 for c in pushes] == [0x01] * 3, f"Pushes not on the stack: {pushes}"
    assert [(c.address - 1) & 0xFF for c in pushes[:2]] == [c.address & 0xFF for c in pushes[1:]], (
        f"Pushes don't walk down the stack: {pushes}"
    )
    assert_trace(vector, [read(0xFFFC, ORIGIN & 0xFF), read(0xFFFD, ORIGIN >> 8)])

    assert_trace(await cpu.cycles(2), [fetch(0x8000, 0xBA), read(0x8001, 0x8E)])
    await run_to_end(cpu, 0x8009)
    stack_pointer = (pushes[-1].address - 1) & 0xFF
    assert cpu.memory[RESULTS] == stack_pointer, (
        f"S should be {stack_pointer:02X} after reset, got {cpu.memory[RESULTS]:02X}"
    )
    assert cpu.memory[RESULTS + 1] & 0b100, "I should be set after reset"


@cocotb.test()
async def test_reset_mid_instruction(dut: "DUT"):
    """Reset can interrupt an instruction partway through, and still lands on
    the reset vector."""
    cpu = await boot(dut, [
        0xA9, 0x42,         # 8000 LDA #$42
        0x8D, 0x00, 0x02,   # 8002 STA $0200
        *jmp_self(0x8005),  # 8005 JMP *
    ])
    await run_to_end(cpu, 0x8005)
    # Loop back to the start, and reset partway through the store's operand
    # fetch the second time around
    cpu.load(0x8005, [0x4C, 0x00, 0x80])
    await cpu.run_until_fetch(0x8002)
    await cpu.cycles(2)

    await cpu.reset()
    assert_trace(await cpu.cycles(1), [fetch(ORIGIN, 0xA9)])


# endregion

# region Cycle timing


@cocotb.test()
async def test_load_store_jump_timing(dut: "DUT"):
    """LDA #, STA abs and JMP abs take 2, 4 and 3 cycles, with the operand
    reads and the store on the documented cycles."""
    cpu = await boot(dut, [
        0xA9, 0x42,         # 8000 LDA #$42
        0x8D, 0x00, 0x02,   # 8002 STA $0200
        *jmp_self(0x8005),  # 8005 JMP *
    ])
    assert_trace(await cpu.cycles(12), [
        fetch(0x8000, 0xA9),
        read(0x8001, 0x42),
        fetch(0x8002, 0x8D),
        read(0x8003, 0x00),
        read(0x8004, 0x02),
        write(0x0200, 0x42),
        fetch(0x8005, 0x4C),
        read(0x8006, 0x05),
        read(0x8007, 0x80),
        fetch(0x8005, 0x4C),
        read(0x8006, 0x05),
        read(0x8007, 0x80),
    ])


@cocotb.test()
async def test_implied_timing(dut: "DUT"):
    """Single-byte instructions take 2 cycles, and read (and discard) the
    next byte."""
    cpu = await boot(dut, [
        0xE8,               # 8000 INX
        0xCA,               # 8001 DEX
        0xEA,               # 8002 NOP
        *jmp_self(0x8003),  # 8003 JMP *
    ])
    assert_trace(await cpu.cycles(7), [
        fetch(0x8000, 0xE8),
        read(0x8001, 0xCA),
        fetch(0x8001, 0xCA),
        read(0x8002, 0xEA),
        fetch(0x8002, 0xEA),
        read(0x8003, 0x4C),
        fetch(0x8003, 0x4C),
    ])


@cocotb.test()
async def test_zero_page_timing(dut: "DUT"):
    """Zero page stores take 3 cycles, and zero page read-modify-write
    instructions take 5, writing the old value back before the new one."""
    cpu = await boot(dut, [
        0xA9, 0x81,         # 8000 LDA #$81
        0x85, 0x10,         # 8002 STA $10
        0x06, 0x10,         # 8004 ASL $10
        *jmp_self(0x8006),  # 8006 JMP *
    ])
    assert_trace(await cpu.cycles(11), [
        fetch(0x8000, 0xA9),
        read(0x8001, 0x81),
        fetch(0x8002, 0x85),
        read(0x8003, 0x10),
        write(0x0010, 0x81),
        fetch(0x8004, 0x06),
        read(0x8005, 0x10),
        read(0x0010, 0x81),
        write(0x0010, 0x81),
        write(0x0010, 0x02),
        fetch(0x8006, 0x4C),
    ])


@cocotb.test()
async def test_indexed_page_cross_timing(dut: "DUT"):
    """Indexed reads take an extra cycle when the index carries into the next
    page. The extra cycle reads from the address before the carry is fixed."""
    cpu = await boot(dut, [
        0xA2, 0x10,         # 8000 LDX #$10
        0xBD, 0x00, 0x90,   # 8002 LDA $9000,X (no page cross)
        0xBD, 0xF8, 0x90,   # 8005 LDA $90F8,X (page cross)
        *jmp_self(0x8008),  # 8008 JMP *
    ])
    cpu.memory[0x9010] = 0x11
    cpu.memory[0x9008] = 0x22
    cpu.memory[0x9108] = 0x33
    assert_trace(await cpu.cycles(12), [
        fetch(0x8000, 0xA2),
        read(0x8001, 0x10),
        fetch(0x8002, 0xBD),
        read(0x8003, 0x00),
        read(0x8004, 0x90),
        read(0x9010, 0x11),
        fetch(0x8005, 0xBD),
        read(0x8006, 0xF8),
        read(0x8007, 0x90),
        read(0x9008, 0x22),
        read(0x9108, 0x33),
        fetch(0x8008, 0x4C),
    ])


@cocotb.test()
async def test_branch_timing(dut: "DUT"):
    """A branch takes 2 cycles if it isn't taken, and 3 if it is. A taken
    branch reads (and discards) the next opcode."""
    cpu = await boot(dut, [
        0xA2, 0x00,         # 8000 LDX #$00 (Z set)
        0xD0, 0x10,         # 8002 BNE +$10 (not taken)
        0xF0, 0x01,         # 8004 BEQ +$01 (taken, to 8007)
        0xEA,               # 8006 NOP (skipped)
        0xF0, 0x77,         # 8007 BEQ +$77 (taken, to 8080)
    ])
    cpu.load(0x8080, jmp_self(0x8080))
    assert_trace(await cpu.cycles(11), [
        fetch(0x8000, 0xA2),
        read(0x8001, 0x00),
        fetch(0x8002, 0xD0),
        read(0x8003, 0x10),
        fetch(0x8004, 0xF0),
        read(0x8005, 0x01),
        read(0x8006, 0xEA),
        fetch(0x8007, 0xF0),
        read(0x8008, 0x77),
        read(0x8009, 0x00),
        fetch(0x8080, 0x4C),
    ])


@cocotb.test()
async def test_branch_page_cross_timing(dut: "DUT"):
    """A taken branch to another page takes an extra cycle, which reads from
    the target address before the high byte is fixed."""
    cpu = await boot(dut, [
        0x4C, 0xF0, 0x80,   # 8000 JMP $80F0
    ])
    cpu.load(0x80F0, [
        0xA2, 0x00,         # 80F0 LDX #$00 (Z set)
        0xF0, 0x20,         # 80F2 BEQ +$20 (taken, to 8114)
    ])
    cpu.load(0x8114, jmp_self(0x8114))
    assert_trace(await cpu.cycles(11), [
        fetch(0x8000, 0x4C),
        read(0x8001, 0xF0),
        read(0x8002, 0x80),
        fetch(0x80F0, 0xA2),
        read(0x80F1, 0x00),
        fetch(0x80F2, 0xF0),
        read(0x80F3, 0x20),
        read(0x80F4, 0x00),
        read(0x8014, 0x00),
        fetch(0x8114, 0x4C),
        read(0x8115, 0x14),
    ])


@cocotb.test()
async def test_stack_timing(dut: "DUT"):
    """JSR takes 6 cycles and pushes the address of its last byte, high byte
    first. RTS takes 6, and pulls it back. PHA takes 3 and PLA takes 4."""
    cpu = await boot(dut, [
        0xA2, 0xFF,         # 8000 LDX #$FF
        0x9A,               # 8002 TXS
        0x20, 0x00, 0x90,   # 8003 JSR $9000
        *jmp_self(0x8006),  # 8006 JMP *
    ])
    cpu.load(0x9000, [
        0xA9, 0x5A,         # 9000 LDA #$5A
        0x48,               # 9002 PHA
        0x68,               # 9003 PLA
        0x60,               # 9004 RTS
    ])
    assert_trace(await cpu.cycles(26), [
        fetch(0x8000, 0xA2),
        read(0x8001, 0xFF),
        fetch(0x8002, 0x9A),
        read(0x8003, 0x20),
        # JSR
        fetch(0x8003, 0x20),
        read(0x8004, 0x00),
        read(0x01FF, 0x00),
        write(0x01FF, 0x80),
        write(0x01FE, 0x05),
        read(0x8005, 0x90),
        # LDA #
        fetch(0x9000, 0xA9),
        read(0x9001, 0x5A),
        # PHA
        fetch(0x9002, 0x48),
        read(0x9003, 0x68),
        write(0x01FD, 0x5A),
        # PLA reads the stack before incrementing S, then pulls
        fetch(0x9003, 0x68),
        read(0x9004, 0x60),
        read(0x01FC, 0x00),
        read(0x01FD, 0x5A),
        # RTS reads the stack before incrementing S, then pulls PC and
        # increments it past the JSR
        fetch(0x9004, 0x60),
        read(0x9005, 0x00),
        read(0x01FD, 0x5A),
        read(0x01FE, 0x05),
        read(0x01FF, 0x80),
        read(0x8005, 0x90),
        fetch(0x8006, 0x4C),
    ])


# endregion

# region Programs


@cocotb.test()
async def test_count_down_loop(dut: "DUT"):
    """A DEX/BNE loop runs the right number of times."""
    cpu = await boot(dut, [
        0xA2, 0x05,         # 8000 LDX #$05
        0xA0, 0x00,         # 8002 LDY #$00
        0xC8,               # 8004 loop: INY
        0xCA,               # 8005 DEX
        0xD0, 0xFC,         # 8006 BNE loop
        0x8E, 0x00, 0x02,   # 8008 STX $0200
        0x8C, 0x01, 0x02,   # 800B STY $0201
        *jmp_self(0x800E),  # 800E JMP *
    ])
    await run_to_end(cpu, 0x800E)
    assert results(cpu, 2) == [0x00, 0x05]


@cocotb.test()
async def test_arithmetic_flags(dut: "DUT"):
    """ADC and SBC set the result, carry and overflow, and PHP pushes P with
    the B and unused bits set."""
    cpu = await boot(dut, [
        0x18,               # 8000 CLC
        0xA9, 0x7F,         # 8001 LDA #$7F
        0x69, 0x01,         # 8003 ADC #$01  -> $80, N V
        0x08,               # 8005 PHP
        0x8D, 0x00, 0x02,   # 8006 STA $0200
        0x68,               # 8009 PLA
        0x8D, 0x01, 0x02,   # 800A STA $0201
        0x38,               # 800D SEC
        0xA9, 0x10,         # 800E LDA #$10
        0xE9, 0x20,         # 8010 SBC #$20  -> $F0, N, borrow
        0x08,               # 8012 PHP
        0x8D, 0x02, 0x02,   # 8013 STA $0202
        0x68,               # 8016 PLA
        0x8D, 0x03, 0x02,   # 8017 STA $0203
        0x18,               # 801A CLC
        0xA9, 0xFF,         # 801B LDA #$FF
        0x69, 0x01,         # 801D ADC #$01  -> $00, Z C
        0x08,               # 801F PHP
        0x68,               # 8020 PLA
        0x8D, 0x04, 0x02,   # 8021 STA $0204
        *jmp_self(0x8024),  # 8024 JMP *
    ])
    await run_to_end(cpu, 0x8024)
    # I is still set from the reset
    #                         NV1BDIZC
    assert results(cpu, 5) == [0x80, 0b11110100, 0xF0, 0b10110100, 0b00110111]


@cocotb.test()
async def test_logic_and_transfers(dut: "DUT"):
    """AND, ORA and EOR, and moving values between A, X and Y."""
    cpu = await boot(dut, [
        0xA9, 0xF0,         # 8000 LDA #$F0
        0x29, 0x3C,         # 8002 AND #$3C  -> $30
        0x8D, 0x00, 0x02,   # 8004 STA $0200
        0x09, 0x0F,         # 8007 ORA #$0F  -> $3F
        0x8D, 0x01, 0x02,   # 8009 STA $0201
        0x49, 0xFF,         # 800C EOR #$FF  -> $C0
        0x8D, 0x02, 0x02,   # 800E STA $0202
        0xAA,               # 8011 TAX
        0xE8,               # 8012 INX       -> $C1
        0x8E, 0x03, 0x02,   # 8013 STX $0203
        0xA8,               # 8016 TAY
        0x88,               # 8017 DEY       -> $BF
        0x8C, 0x04, 0x02,   # 8018 STY $0204
        0x98,               # 801B TYA
        0x8D, 0x05, 0x02,   # 801C STA $0205
        *jmp_self(0x801F),  # 801F JMP *
    ])
    await run_to_end(cpu, 0x801F)
    assert results(cpu, 6) == [0x30, 0x3F, 0xC0, 0xC1, 0xBF, 0xBF]


@cocotb.test()
async def test_compare_and_bit(dut: "DUT"):
    """CMP, CPX and BIT set the flags without changing the registers."""
    cpu = await boot(dut, [
        0xA9, 0x05,         # 8000 LDA #$05
        0xC9, 0x05,         # 8002 CMP #$05  -> Z C
        0x08,               # 8004 PHP
        0x68,               # 8005 PLA
        0x8D, 0x00, 0x02,   # 8006 STA $0200
        0xA2, 0x03,         # 8009 LDX #$03
        0xE0, 0x04,         # 800B CPX #$04  -> N
        0x08,               # 800D PHP
        0x68,               # 800E PLA
        0x8D, 0x01, 0x02,   # 800F STA $0201
        0xA9, 0xC0,         # 8012 LDA #$C0
        0x85, 0x10,         # 8014 STA $10
        0xA9, 0x00,         # 8016 LDA #$00
        0x24, 0x10,         # 8018 BIT $10   -> N V Z
        0x08,               # 801A PHP
        0x68,               # 801B PLA
        0x8D, 0x02, 0x02,   # 801C STA $0202
        *jmp_self(0x801F),  # 801F JMP *
    ])
    await run_to_end(cpu, 0x801F)
    # I is still set from the reset
    #                         NV1BDIZC
    assert results(cpu, 3) == [0b00110111, 0b10110100, 0b11110110]


@cocotb.test()
async def test_shifts_and_read_modify_write(dut: "DUT"):
    """ASL, ROR and INC on memory, and LSR and ROL on the accumulator, with
    the carry passed from one to the next."""
    cpu = await boot(dut, [
        0xA9, 0x81,         # 8000 LDA #$81
        0x85, 0x10,         # 8002 STA $10
        0x06, 0x10,         # 8004 ASL $10   -> $02, C
        0x66, 0x10,         # 8006 ROR $10   -> $81
        0xE6, 0x10,         # 8008 INC $10   -> $82
        0xA5, 0x10,         # 800A LDA $10
        0x4A,               # 800C LSR A     -> $41
        0x8D, 0x00, 0x02,   # 800D STA $0200
        0xA5, 0x10,         # 8010 LDA $10
        0x8D, 0x01, 0x02,   # 8012 STA $0201
        0x2A,               # 8015 ROL A     -> $04, C
        0x8D, 0x02, 0x02,   # 8016 STA $0202
        0x6A,               # 8019 ROR A     -> $82
        0x8D, 0x03, 0x02,   # 801A STA $0203
        *jmp_self(0x801D),  # 801D JMP *
    ])
    await run_to_end(cpu, 0x801D)
    assert results(cpu, 4) == [0x41, 0x82, 0x04, 0x82]


@cocotb.test()
async def test_addressing_modes(dut: "DUT"):
    """Indexed, indirect indexed, indexed indirect and indirect jumps."""
    cpu = await boot(dut, [
        0xA2, 0x10,         # 8000 LDX #$10
        0xBD, 0xF8, 0x90,   # 8002 LDA $90F8,X -> [$9108]
        0x8D, 0x00, 0x02,   # 8005 STA $0200
        0xA0, 0x01,         # 8008 LDY #$01
        0xB9, 0x00, 0x91,   # 800A LDA $9100,Y -> [$9101]
        0x8D, 0x01, 0x02,   # 800D STA $0201
        0xA9, 0x00,         # 8010 LDA #$00
        0x85, 0x20,         # 8012 STA $20
        0xA9, 0x91,         # 8014 LDA #$91
        0x85, 0x21,         # 8016 STA $21
        0xA0, 0x02,         # 8018 LDY #$02
        0xB1, 0x20,         # 801A LDA ($20),Y -> [$9102]
        0x8D, 0x02, 0x02,   # 801C STA $0202
        0xA9, 0x03,         # 801F LDA #$03
        0x85, 0x24,         # 8021 STA $24
        0xA9, 0x91,         # 8023 LDA #$91
        0x85, 0x25,         # 8025 STA $25
        0xA2, 0x04,         # 8027 LDX #$04
        0xA1, 0x20,         # 8029 LDA ($20,X) -> [$9103]
        0x8D, 0x03, 0x02,   # 802B STA $0203
        0xB5, 0x1C,         # 802E LDA $1C,X -> [$20]
        0x8D, 0x04, 0x02,   # 8030 STA $0204
        0x6C, 0x00, 0x92,   # 8033 JMP ($9200) -> $8040
    ])
    cpu.load(0x9100, [0xA0, 0xA1, 0xA2, 0xA3])
    cpu.memory[0x9108] = 0x5A
    cpu.set_vector(0x9200, 0x8040)
    cpu.load(0x8040, jmp_self(0x8040))
    await run_to_end(cpu, 0x8040)
    assert results(cpu, 5) == [0x5A, 0xA1, 0xA2, 0xA3, 0x00]


@cocotb.test()
async def test_subroutines(dut: "DUT"):
    """Nested JSR and RTS, with values passed back on the stack."""
    cpu = await boot(dut, [
        0xA2, 0xFF,         # 8000 LDX #$FF
        0x9A,               # 8002 TXS
        0x20, 0x00, 0x90,   # 8003 JSR outer
        0x8D, 0x01, 0x02,   # 8006 STA $0201
        0xBA,               # 8009 TSX
        0x8E, 0x02, 0x02,   # 800A STX $0202
        *jmp_self(0x800D),  # 800D JMP *
    ])
    cpu.load(0x9000, [
        0x20, 0x10, 0x90,   # 9000 outer: JSR inner
        0x8D, 0x00, 0x02,   # 9003 STA $0200
        0xA9, 0x22,         # 9006 LDA #$22
        0x60,               # 9008 RTS
    ])
    cpu.load(0x9010, [
        0xA9, 0x11,         # 9010 inner: LDA #$11
        0x60,               # 9012 RTS
    ])
    await run_to_end(cpu, 0x800D)
    assert results(cpu, 3) == [0x11, 0x22, 0xFF]


# endregion

# region Interrupts


@cocotb.test()
async def test_brk_and_rti(dut: "DUT"):
    """BRK pushes PC+2 and P, sets I, and jumps through the IRQ vector. RTI
    pulls P and PC back, returning after the BRK's padding byte."""
    cpu = await boot(dut, [
        0xA2, 0xFF,         # 8000 LDX #$FF
        0x9A,               # 8002 TXS
        0xA2, 0x01,         # 8003 LDX #$01 (clears N and Z)
        0xB8,               # 8005 CLV
        0x58,               # 8006 CLI
        0x38,               # 8007 SEC
        0x00, 0xEA,         # 8008 BRK, padding
        0x08,               # 800A PHP
        0x68,               # 800B PLA
        0x8D, 0x01, 0x02,   # 800C STA $0201
        *jmp_self(0x800F),  # 800F JMP *
    ])
    cpu.set_vector(IRQ_VECTOR, 0x9000)
    cpu.load(0x9000, [
        0x08,               # 9000 PHP
        0x68,               # 9001 PLA
        0x8D, 0x02, 0x02,   # 9002 STA $0202
        0x18,               # 9005 CLC
        0xA9, 0x77,         # 9006 LDA #$77
        0x8D, 0x00, 0x02,   # 9008 STA $0200
        0x40,               # 900B RTI
    ])
    await cpu.run_until_fetch(0x8008)
    assert_trace(await cpu.cycles(8), [
        fetch(0x8008, 0x00),
        read(0x8009, 0xEA),
        write(0x01FF, 0x80),
        write(0x01FE, 0x0A),
        #               NV1BDIZC
        write(0x01FD, 0b00110001),
        read(0xFFFE, 0x00),
        read(0xFFFF, 0x90),
        fetch(0x9000, 0x08),
    ])
    await run_to_end(cpu, 0x800F)
    #                           NV1BDIZC
    assert results(cpu, 3) == [0x77, 0b00110001, 0b00110101]


@cocotb.test()
async def test_irq(dut: "DUT"):
    """An IRQ is ignored while I is set. After CLI, it's taken once the next
    instruction finishes. It pushes P with B clear, and the handler runs with
    I set."""
    cpu = await boot(dut, [
        0xA2, 0xFF,         # 8000 LDX #$FF
        0x9A,               # 8002 TXS
        0xA0, 0x00,         # 8003 LDY #$00
        0x78,               # 8005 SEI
        0xEA,               # 8006 NOP
        0xEA,               # 8007 NOP
        0x58,               # 8008 CLI
        0xC8,               # 8009 loop: INY
        0x4C, 0x09, 0x80,   # 800A JMP loop
    ])
    cpu.set_vector(IRQ_VECTOR, 0x9000)
    cpu.load(0x9000, [
        0x8C, 0x00, 0x02,   # 9000 STY $0200
        0x08,               # 9003 PHP
        0x68,               # 9004 PLA
        0x8D, 0x01, 0x02,   # 9005 STA $0201
        *jmp_self(0x9008),  # 9008 JMP *
    ])
    await cpu.run_until_fetch(0x8006)
    dut.irq_pin_n_IRQ.value = 0
    before_cli = await cpu.run_until_fetch(0x8008, max_cycles=10)
    assert all(c.read for c in before_cli), "Took the IRQ while I was set"
    await run_to_end(cpu, 0x9008, max_cycles=50)
    dut.irq_pin_n_IRQ.value = 1

    pushed_pc = cpu.memory[0x01FF] << 8 | cpu.memory[0x01FE]
    assert pushed_pc == 0x800A, f"Expected to return to 800A, after one INY, got {pushed_pc:04X}"
    assert cpu.memory[RESULTS] == 1, "Expected one INY before the IRQ"
    assert cpu.memory[0x01FD] & 0b100 == 0, "Pushed P with I set"
    assert cpu.memory[0x01FD] & 0b1_0000 == 0, "Pushed P with B set for a hardware interrupt"
    assert cpu.memory[RESULTS + 1] & 0b100, "I not set in the handler"


@cocotb.test()
async def test_nmi(dut: "DUT"):
    """An NMI is edge-triggered, and taken even while I is set."""
    cpu = await boot(dut, [
        0xA2, 0xFF,         # 8000 LDX #$FF
        0x9A,               # 8002 TXS
        0x78,               # 8003 SEI
        0xA9, 0x00,         # 8004 LDA #$00
        0x8D, 0x00, 0x02,   # 8006 STA $0200
        *jmp_self(0x8009),  # 8009 JMP *
    ])
    cpu.set_vector(NMI_VECTOR, 0x9000)
    cpu.load(0x9000, [
        0xEE, 0x00, 0x02,   # 9000 INC $0200
        0x40,               # 9003 RTI
    ])
    await run_to_end(cpu, 0x8009)
    dut.nmi_pin_n_NMI.value = 0
    await cpu.run_until_fetch(0x9003, max_cycles=50)
    await cpu.run_until_fetch(0x8009, max_cycles=50)
    # Holding /NMI low doesn't trigger another one
    await cpu.cycles(30)
    assert cpu.memory[RESULTS] == 1, "NMI not taken exactly once"
    dut.nmi_pin_n_NMI.value = 1
    await cpu.cycles(6)
    dut.nmi_pin_n_NMI.value = 0
    await cpu.cycles(30)
    dut.nmi_pin_n_NMI.value = 1
    assert cpu.memory[RESULTS] == 2, "Second NMI edge not taken"


# endregion
