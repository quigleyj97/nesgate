"""End-to-end tests of the 2A03, running programs from memory.

These check what the APU and DMA controllers do to the CPU and its bus,
against the documented behaviour of a real 2A03: the sprite DMA's bus trace
and its 513 or 514 cycle stall, the DMC's 3 or 4 cycle fetches, `$4015`, the
frame interrupt, and the register decoder's quirks.

The 2A03's decimal mode is cut out, but the decimal adjust adders aren't
built yet (see the `DAA` and `DSA` notes in the 6502 core), so that cut can't
be seen on the bus yet.
"""

from typing import TYPE_CHECKING

import cocotb

from cores.mos_6502.harness import IRQ_VECTOR, RESET_VECTOR, BusCycle
from cores.ricoh_2a03.harness import Ricoh2A03Harness

if TYPE_CHECKING:
    from ricoh_2a03 import Ricoh2a03 as DUT

#: Where the test programs start
ORIGIN = 0x8000
#: Where the test programs store their results
RESULT = 0x0200


async def boot(dut: "DUT", program: list[int], debug: bool = False,
               irq_handler: list[int] | None = None) -> Ricoh2A03Harness:
    cpu = Ricoh2A03Harness(dut, debug=debug)
    cpu.load(ORIGIN, program)
    cpu.set_vector(RESET_VECTOR, ORIGIN)
    if irq_handler is not None:
        cpu.load(0x9000, irq_handler)
        cpu.set_vector(IRQ_VECTOR, 0x9000)
    await cpu.start()
    await cpu.reset()
    return cpu


def index_of(trace: list[BusCycle], match, start: int = 0) -> int:
    for i in range(start, len(trace)):
        if match(trace[i]):
            return i
    raise AssertionError("No matching cycle in the trace")


@cocotb.test()
async def test_program_runs_end_to_end(dut: "DUT"):
    """Reset, fetch, read operands, and write a result to memory."""
    cpu = await boot(dut, [
        0xA9, 0x05,         # 8000 LDA #$05
        0x18,               # 8002 CLC
        0x69, 0x03,         # 8003 ADC #$03
        0x8D, 0x00, 0x02,   # 8005 STA $0200
        0x4C, 0x08, 0x80,   # 8008 JMP *
    ])
    await cpu.run_until_fetch(0x8008)
    assert cpu.memory[RESULT] == 0x08, f"Stored {cpu.memory[RESULT]:#04x}, expected 0x08"


async def sprite_dma(dut: "DUT", lead_in: list[int]) -> int:
    """Run a sprite DMA from page 2, check its bus trace, and return how many
    cycles it stalled the CPU for."""
    store = ORIGIN + len(lead_in) + 2
    after = store + 3
    cpu = await boot(dut, lead_in + [
        0xA9, 0x02,                         # LDA #$02
        0x8D, 0x14, 0x40,                   # STA $4014
        0xEA,                               # NOP
        0x4C, after & 0xFF, after >> 8,     # JMP to the NOP
    ])
    page = bytes((i * 7 + 0x5A) & 0xFF for i in range(256))
    cpu.load(0x0200, page)
    await cpu.cycles(700)
    trace = cpu.trace

    write = index_of(trace, lambda c: not c.read and c.address == 0x4014)
    first = index_of(trace, lambda c: c.address == 0x0200, write)
    for cycle in trace[write + 1:first]:
        assert cycle.read and cycle.address == after, f"Stalled on {cycle}"
    for i in range(256):
        read, written = trace[first + 2 * i], trace[first + 2 * i + 1]
        assert read.read and read.address == 0x0200 + i, f"Byte {i}: {read}"
        assert not written.read and written.address == 0x2004, f"Byte {i}: {written}"
        assert written.data == page[i], f"Byte {i}: wrote {written.data:#04x}, expected {page[i]:#04x}"
    resume = first + 512
    assert trace[resume].sync and trace[resume].address == after, (
        f"Resumed with {trace[resume]}"
    )
    assert trace[resume + 1].address == after + 1, "The NOP didn't run after the DMA"
    return resume - write - 1


#: The sprite DMA stalls seen by the tests below, which run in order
SPRITE_DMA_STALLS: list[int] = []


@cocotb.test()
async def test_sprite_dma(dut: "DUT"):
    """A sprite DMA copies the page to $2004, a read then a write per byte,
    and stalls the CPU for 513 or 514 cycles."""
    stall = await sprite_dma(dut, [])
    assert stall in (513, 514), f"Stalled for {stall} cycles"
    SPRITE_DMA_STALLS.append(stall)


@cocotb.test()
async def test_sprite_dma_other_half(dut: "DUT"):
    """Starting the DMA an odd number of cycles later (with a 3-cycle
    instruction first) changes the stall by one cycle."""
    stall = await sprite_dma(dut, [0xA6, 0x00])  # LDX $00
    SPRITE_DMA_STALLS.append(stall)
    assert sorted(SPRITE_DMA_STALLS) == [513, 514], f"Stalled for {SPRITE_DMA_STALLS} cycles"


@cocotb.test()
async def test_status_and_open_bus(dut: "DUT"):
    """$4015 reads the length counters' status. Bit 5 isn't driven, so it
    reads whatever was last on the bus: the dummy read before a page-crossing
    indexed read."""
    cpu = await boot(dut, [
        0xA9, 0x0F,         # 8000 LDA #$0F
        0x8D, 0x15, 0x40,   # 8002 STA $4015      ; enable every channel
        0xA9, 0x08,         # 8005 LDA #$08
        0x8D, 0x03, 0x40,   # 8007 STA $4003      ; and load their lengths
        0x8D, 0x07, 0x40,   # 800A STA $4007
        0x8D, 0x0B, 0x40,   # 800D STA $400B
        0x8D, 0x0F, 0x40,   # 8010 STA $400F
        0xAD, 0x15, 0x40,   # 8013 LDA $4015      ; open bus is $40
        0x8D, 0x00, 0x02,   # 8016 STA $0200
        0xA2, 0x20,         # 8019 LDX #$20
        0xBD, 0xF5, 0x3F,   # 801B LDA $3FF5,X    ; dummy read of $3F15 first
        0x8D, 0x01, 0x02,   # 801E STA $0201
        0x4C, 0x21, 0x80,   # 8021 JMP *
    ])
    cpu.memory[0x3F15] = 0xFF
    await cpu.run_until_fetch(0x8021)
    assert cpu.memory[0x0200] == 0x0F, f"$4015 read {cpu.memory[0x0200]:#04x}, expected 0x0F"
    assert cpu.memory[0x0201] == 0x2F, f"$4015 read {cpu.memory[0x0201]:#04x} after $FF"


@cocotb.test()
async def test_frame_interrupt(dut: "DUT"):
    """In 4-step mode the frame counter interrupts about 29830 cycles after a
    write to $4017. $4015 bit 6 reads the flag, and reading it clears it."""
    cpu = await boot(dut, [
        0xA9, 0x00,         # 8000 LDA #$00
        0x8D, 0x17, 0x40,   # 8002 STA $4017
        0x58,               # 8005 CLI
        0x4C, 0x06, 0x80,   # 8006 JMP *
    ], irq_handler=[
        0xAD, 0x15, 0x40,   # 9000 LDA $4015
        0x8D, 0x00, 0x02,   # 9003 STA $0200
        0xAD, 0x15, 0x40,   # 9006 LDA $4015
        0x8D, 0x01, 0x02,   # 9009 STA $0201
        0x4C, 0x0C, 0x90,   # 900C JMP *
    ])
    await cpu.run_until_fetch(0x900C, max_cycles=30000)
    trace = cpu.trace
    write = index_of(trace, lambda c: not c.read and c.address == 0x4017)
    vector = index_of(trace, lambda c: c.read and c.address == IRQ_VECTOR)
    # The flag sets 29828 cycles after the restart, which is 3 or 4 cycles
    # after the write. The CPU then finishes its JMP and pushes its state.
    delay = vector - write
    assert 29831 + 5 <= delay <= 29832 + 9, f"IRQ vector read {delay} cycles after the write"
    assert cpu.memory[0x0200] == 0x40, f"$4015 read {cpu.memory[0x0200]:#04x} in the handler"
    assert cpu.memory[0x0201] == 0x00, "Reading $4015 didn't clear the flag"


def dmc_program(loop_body: list[int], control: int = 0x0F, length: int = 0x00) -> list[int]:
    """Start a DMC sample at $C000, then run `loop_body` forever."""
    prologue = [
        0xA9, control,      # 8000 LDA #control
        0x8D, 0x10, 0x40,   # 8002 STA $4010
        0xA9, 0x00,         # 8005 LDA #$00
        0x8D, 0x12, 0x40,   # 8007 STA $4012      ; $C000
        0xA9, length,       # 800A LDA #length
        0x8D, 0x13, 0x40,   # 800C STA $4013
        0xA9, 0x10,         # 800F LDA #$10
        0x8D, 0x15, 0x40,   # 8011 STA $4015      ; enable
    ]
    loop = ORIGIN + len(prologue)
    return prologue + loop_body + [0x4C, loop & 0xFF, loop >> 8]


@cocotb.test()
async def test_dmc_fetch_steals_cycles(dut: "DUT"):
    """A DMC fetch reads the sample byte from $C000, stalling the CPU's read
    for 3 or 4 cycles in all: the CPU repeats its read until the fetch is
    done."""
    cpu = await boot(dut, dmc_program([0xA5, 0x00]))  # LDA $00
    cpu.memory[0xC000] = 0xAA
    await cpu.cycles(300)
    trace = cpu.trace
    fetches = [i for i, c in enumerate(trace) if c.address == 0xC000]
    assert len(fetches) == 1, f"{len(fetches)} fetches of a 1-byte sample"
    fetch = fetches[0]
    assert trace[fetch].read and trace[fetch].data == 0xAA
    resumed = trace[fetch + 1]
    assert resumed.read, f"Resumed with {resumed}"
    repeats = 0
    while trace[fetch - 1 - repeats] == resumed:
        repeats += 1
    assert repeats + 1 in (3, 4), f"The fetch took {repeats + 1} cycles"


@cocotb.test()
async def test_dmc_fetch_double_reads_controller(dut: "DUT"):
    """A DMC fetch that lands on a read of $4016 strobes /IN0 twice: the CPU's
    read is repeated either side of the fetch, and during the fetch the
    register decoder sees the DMC's address on the pins and selects nothing.
    That's the controller bit that real NES games lose."""
    cpu = await boot(dut, dmc_program([0xAD, 0x16, 0x40] * 10, control=0x4F))  # LDA $4016
    await cpu.cycles(12000)
    trace = cpu.trace
    strobes = [in0 for in0, _ in cpu.input_strobes]
    hits = 0
    for fetch in (i for i, c in enumerate(trace) if c.address == 0xC000):
        if trace[fetch + 1].address != 0x4016:
            continue
        hits += 1
        # /IN0 around the fetch: low (stalled reads), high (fetch), low (read)
        assert strobes[fetch - 1] == 0 and strobes[fetch] == 1 and strobes[fetch + 1] == 0, (
            f"/IN0 around the fetch: {strobes[fetch - 4:fetch + 3]}"
        )
    assert hits, "No fetch landed on a $4016 read"
    # A read of $4016 away from any fetch strobes /IN0 once, for one cycle
    fetches = [i for i, c in enumerate(trace) if c.address == 0xC000]
    plain = index_of(trace, lambda c: c.address == 0x4016, fetches[0] + 20)
    assert strobes[plain - 1:plain + 2] == [1, 0, 1], f"/IN0 {strobes[plain - 1:plain + 2]}"


@cocotb.test()
async def test_square_waveform(dut: "DUT"):
    """A program can play square 0: a 50% duty cycle with period $20 is high
    for 264 cycles and low for 264."""
    cpu = await boot(dut, [
        0xA9, 0x01,         # 8000 LDA #$01
        0x8D, 0x15, 0x40,   # 8002 STA $4015
        0xA9, 0xBF,         # 8005 LDA #$BF       ; 50%, halt, constant 15
        0x8D, 0x00, 0x40,   # 8007 STA $4000
        0xA9, 0x20,         # 800A LDA #$20
        0x8D, 0x02, 0x40,   # 800C STA $4002
        0xA9, 0x00,         # 800F LDA #$00
        0x8D, 0x03, 0x40,   # 8011 STA $4003
        0x4C, 0x14, 0x80,   # 8014 JMP *
    ])
    await cpu.cycles(1800)
    levels = [o.square0 for o in cpu.outputs]
    runs: list[list[int]] = []
    for level in levels:
        if runs and runs[-1][0] == level:
            runs[-1][1] += 1
        else:
            runs.append([level, 1])
    steady = runs[2:-1]
    assert steady, f"No waveform: {runs}"
    assert all(length == 264 for _, length in steady), f"Runs {steady}"
    assert {level for level, _ in steady} == {0, 15}


@cocotb.test()
async def test_out_pins(dut: "DUT"):
    """Writing $4016 sets the OUT pins."""
    cpu = await boot(dut, [
        0xA9, 0x05,         # 8000 LDA #$05
        0x8D, 0x16, 0x40,   # 8002 STA $4016
        0x4C, 0x05, 0x80,   # 8005 JMP *
    ])
    await cpu.run_until_fetch(0x8005)
    await cpu.cycles(2)
    assert dut.out_pins_OUT.value == 0b101, f"OUT is {dut.out_pins_OUT.value}"


#: Locks the channels, then reads $4018 and $4019 into $0200 and $0201
DEBUG_PROGRAM = [
    0xA9, 0x1A,         # 8000 LDA #$1A       ; constant volume 10
    0x8D, 0x00, 0x40,   # 8002 STA $4000
    0xA9, 0x80,         # 8005 LDA #$80
    0x8D, 0x1A, 0x40,   # 8007 STA $401A      ; LOCK, triangle step 0
    0xAD, 0x18, 0x40,   # 800A LDA $4018
    0x8D, 0x00, 0x02,   # 800D STA $0200
    0xAD, 0x19, 0x40,   # 8010 LDA $4019
    0x8D, 0x01, 0x02,   # 8013 STA $0201
    0x4C, 0x16, 0x80,   # 8016 JMP *
]


@cocotb.test()
async def test_debug_registers(dut: "DUT"):
    """With DBG high, $401A bit 7 locks the channels, and $4018 and $4019 read
    their outputs: square 0's volume, and the triangle at step 0 (15)."""
    cpu = await boot(dut, DEBUG_PROGRAM, debug=True)
    await cpu.run_until_fetch(0x8016)
    assert cpu.memory[0x0200] == 0x0A, f"$4018 read {cpu.memory[0x0200]:#04x}"
    assert cpu.memory[0x0201] == 0x0F, f"$4019 read {cpu.memory[0x0201]:#04x}"


@cocotb.test()
async def test_no_debug_registers_without_dbg(dut: "DUT"):
    """Without DBG, $4018 and $4019 are just memory (here, the harness's)."""
    cpu = await boot(dut, DEBUG_PROGRAM)
    cpu.memory[0x4018] = 0x77
    cpu.memory[0x4019] = 0x66
    await cpu.run_until_fetch(0x8016)
    assert cpu.memory[0x0200] == 0x77, f"$4018 read {cpu.memory[0x0200]:#04x} without DBG"
