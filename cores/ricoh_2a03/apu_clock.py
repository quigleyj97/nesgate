"""Drives the CPU and APU clocks for the 2A03's entity testbenches.

A CPU cycle is a Phi1 phase followed by a Phi2 phase, each
`METACLOCKS_PER_PHASE` metaclock cycles long, as in the 6502's harness. An APU
cycle is two CPU cycles: ACLK1 is high during the Phi1 of the first, and ACLK2
during the Phi1 of the second (see `aclk_generator.vhdl`). This driver plays
the part of the `aclk_generator`, so a test can check an entity against the
clocks it's documented to see, cycle by cycle.

It drives whichever of `phi1`, `phi2`, `aclk1` and `aclk2` the entity has.
Signals passed to `cycle()` are set for one phase and cleared afterwards, which
is how the register decoder's write strobes (Phi2) and the frame counter's
outputs (Phi1, during ACLK2) look.
"""

from collections.abc import Callable
from typing import Any

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, Timer

#: Each phase must last at least three metaclock cycles
METACLOCKS_PER_PHASE = 4
#: The metaclock's period, in ns
METACLOCK_PERIOD = 2

Signals = dict[str, int]


class ApuClock:
    def __init__(self, dut: Any, drive_aclk: bool = True, watch: tuple[str, ...] = ()):
        self.dut = dut
        self.drive_aclk = drive_aclk
        #: For each watched output, the CPU cycles in which it was high at the
        #: end of Phi1, numbered from 0
        self.pulses: dict[str, list[int]] = {name: [] for name in watch}
        self.clocks = [
            name for name in ("phi1", "phi2", "aclk1", "aclk2")
            if hasattr(dut, name) and (drive_aclk or not name.startswith("aclk"))
        ]
        #: Whether the next CPU cycle's Phi1 has ACLK1 (otherwise ACLK2)
        self.next_is_aclk1 = True
        #: CPU cycles run so far
        self.cycles = 0
        #: Called at the start of every Phi2, after Phi1 has settled. The
        #: signals it returns are set for that Phi2, like `cycle()`'s `phi2`.
        #: A test uses it to answer a DMA's read, for instance.
        self.serve: Callable[[], Signals] | None = None

    async def start(self):
        """Start the metaclock with every clock low."""
        for name in self.clocks:
            getattr(self.dut, name).value = 0
        cocotb.start_soon(Clock(self.dut.metaclock, METACLOCK_PERIOD, unit="ns").start())
        # Phases change on the falling edge, away from the sampling edge
        await FallingEdge(self.dut.metaclock)

    async def _phase(self):
        await Timer(METACLOCKS_PER_PHASE * METACLOCK_PERIOD, unit="ns")

    def _set(self, name: str, value: int):
        if name in self.clocks:
            getattr(self.dut, name).value = value

    async def cycle(self, phi1: Signals | None = None, phi2: Signals | None = None):
        """Run one CPU cycle, setting `phi1` during Phi1 and `phi2` during
        Phi2. Each is cleared at the end of its phase."""
        dut = self.dut
        self._set("phi1", 1)
        self._set("aclk1", int(self.next_is_aclk1))
        self._set("aclk2", int(not self.next_is_aclk1))
        for name, value in (phi1 or {}).items():
            getattr(dut, name).value = value
        await self._phase()
        for name, pulses in self.pulses.items():
            if getattr(dut, name).value == 1:
                pulses.append(self.cycles)
        for name in phi1 or {}:
            getattr(dut, name).value = 0
        self._set("phi1", 0)
        self._set("aclk1", 0)
        self._set("aclk2", 0)

        phi2 = dict(phi2 or {})
        if self.serve is not None:
            phi2 |= self.serve()
        self._set("phi2", 1)
        for name, value in phi2.items():
            getattr(dut, name).value = value
        await self._phase()
        for name in phi2:
            getattr(dut, name).value = 0
        self._set("phi2", 0)

        self.next_is_aclk1 = not self.next_is_aclk1
        self.cycles += 1

    async def cycles_(self, count: int):
        for _ in range(count):
            await self.cycle()

    async def apu_cycle(self, aclk2: Signals | None = None, phi2: Signals | None = None):
        """Run one APU cycle (two CPU cycles, starting with an ACLK1), setting
        `aclk2` during the ACLK2 phase, and `phi2` during the second Phi2."""
        if not self.next_is_aclk1:
            await self.cycle()
        await self.cycle()
        await self.cycle(phi1=aclk2, phi2=phi2)

    async def write(self, strobe: str, value: int, bus: str = "bus_DB_in"):
        """Write `value` to a register: put it on the data bus, and assert its
        strobe, during the next Phi2."""
        await self.cycle(phi2={strobe: 1, bus: value})
