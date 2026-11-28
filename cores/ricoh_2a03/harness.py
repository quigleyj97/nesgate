"""A cocotb test harness for the whole 2A03 (`ricoh_2a03`).

It's the 6502's harness (see `cores/mos_6502/harness.py`), which runs the chip
one CPU cycle at a time against 64 KiB of memory and records every bus cycle,
with the 2A03's differences:

- There's no RDY pin, since the DMA controllers drive the CPU's, and there's a
  DBG pin, held low (retail) unless a test sets `debug`.
- After every cycle it records the channel outputs, so a test can check the
  waveform a program makes, cycle by cycle, and the `/IN0` and `/IN1` pins.

The sprite DMA's writes to `$2004` show up in the trace as writes, and the
DMC's sample fetches as reads, like any other bus cycle.
"""

from dataclasses import dataclass
from typing import TYPE_CHECKING, Any, cast

from cores.mos_6502.harness import BusCycle, Mos6502Harness

if TYPE_CHECKING:
    from ricoh_2a03 import Ricoh2a03 as DUT


@dataclass(frozen=True)
class Outputs:
    """The channel outputs at the end of a cycle."""

    square0: int
    square1: int
    triangle: int
    noise: int
    dmc: int


class Ricoh2A03Harness(Mos6502Harness):
    def __init__(self, dut: "DUT", debug: bool = False):
        # The 6502 harness only touches pins the 2A03 has too, once
        # `_idle_pins` is overridden
        super().__init__(cast(Any, dut))
        self.chip = dut
        self.debug = debug
        #: The channel outputs after each cycle, in step with `trace` (except
        #: while `run_until` holds a cycle back)
        self.outputs: list[Outputs] = []
        #: The `/IN0` and `/IN1` pins during each cycle, in step with `trace`
        self.input_strobes: list[tuple[int, int]] = []

    def _idle_pins(self):
        dut = self.chip
        dut.reset_pin_n_RES.value = 1
        dut.irq_pin_n_IRQ.value = 1
        dut.nmi_pin_n_NMI.value = 1
        dut.debug_pin_DBG.value = int(self.debug)
        dut.data_in.value = 0

    async def _run_cycle(self) -> BusCycle:
        # Hooked here rather than in `cycle()`, which can hand back a cycle
        # `run_until` held back without running a new one
        bus_cycle = await super()._run_cycle()
        dut = self.chip
        self.outputs.append(Outputs(
            square0=int(dut.output_SQA.value),
            square1=int(dut.output_SQB.value),
            triangle=int(dut.output_TRI.value),
            noise=int(dut.output_RND.value),
            dmc=int(dut.output_DMC.value),
        ))
        self.input_strobes.append((int(dut.in0_pin_n_IN0.value), int(dut.in1_pin_n_IN1.value)))
        return bus_cycle

    async def reset(self, held_cycles: int = 4) -> list[BusCycle]:
        sequence = await super().reset(held_cycles)
        self.outputs.clear()
        self.input_strobes.clear()
        return sequence
