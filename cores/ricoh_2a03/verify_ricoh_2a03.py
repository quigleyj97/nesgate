"""End-to-end tests of the 2A03, running programs from memory.

The 2A03 is the 6502 with its decimal mode cut out, but the decimal adjust
adders aren't built yet (see the `DAA` and `DSA` notes in the 6502 core), so
that cut can't be seen on the bus yet. These tests check the wrapper's job for
now: that the pins reach the CPU, which runs a program from reset to the end.
"""

from typing import TYPE_CHECKING

import cocotb

from cores.mos_6502.harness import RESET_VECTOR, Mos6502Harness

if TYPE_CHECKING:
    # The harness is typed for the 6502's pins, which the 2A03 has too
    from mos_6502 import Mos6502 as DUT

#: Where the test program starts
ORIGIN = 0x8000
#: Where the test program stores its result
RESULT = 0x0200


@cocotb.test()
async def test_program_runs_end_to_end(dut: "DUT"):
    """Reset, fetch, read operands, and write a result to memory."""
    cpu = Mos6502Harness(dut)
    cpu.load(ORIGIN, [
        0xA9, 0x05,         # 8000 LDA #$05
        0x18,               # 8002 CLC
        0x69, 0x03,         # 8003 ADC #$03
        0x8D, 0x00, 0x02,   # 8005 STA $0200
        0x4C, 0x08, 0x80,   # 8008 JMP *
    ])
    cpu.set_vector(RESET_VECTOR, ORIGIN)
    await cpu.start()
    await cpu.reset()

    await cpu.run_until_fetch(0x8008)

    assert cpu.memory[RESULT] == 0x08, f"Stored {cpu.memory[RESULT]:#04x}, expected 0x08"
