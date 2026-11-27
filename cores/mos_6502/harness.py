"""A cocotb test harness for the whole CPU (`mos_6502`).

The harness plays the part of the rest of the system: it generates Phi1 and
Phi2 from the metaclock, and models 64 KiB of memory on the address and data
pins. It runs the CPU one cycle at a time, and records every bus cycle, so a
test can check the exact sequence of reads and writes a program makes.

A cycle is a Phi1 phase followed by a Phi2 phase, each `METACLOCKS_PER_PHASE`
metaclock cycles long. The CPU sets up the address, R/W and SYNC during Phi1,
so they're sampled once Phi1 ends. On a read, memory drives the data pins for
all of Phi2. On a write, the CPU drives them during Phi2, and memory stores
the value at the end of it.
"""

from collections.abc import Callable, Iterable
from dataclasses import dataclass
from typing import TYPE_CHECKING

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge

if TYPE_CHECKING:
    from mos_6502 import Mos6502 as DUT

#: Each phase must last at least three metaclock cycles (see clocks.md)
METACLOCKS_PER_PHASE = 4

RESET_VECTOR = 0xFFFC
NMI_VECTOR = 0xFFFA
IRQ_VECTOR = 0xFFFE


@dataclass(frozen=True)
class BusCycle:
    """One CPU cycle, as seen on the pins."""

    address: int
    #: True for a read, False for a write (the R/W pin)
    read: bool
    #: The byte memory returned, or the byte the CPU wrote
    data: int
    #: True for an opcode fetch (the SYNC pin)
    sync: bool

    def __str__(self) -> str:
        kind = "fetch" if self.sync else ("read " if self.read else "write")
        return f"{kind} {self.address:04X} {self.data:02X}"


def read(address: int, data: int) -> BusCycle:
    """An operand or data read, for writing expected bus traces."""
    return BusCycle(address, True, data, False)


def fetch(address: int, data: int) -> BusCycle:
    """An opcode fetch, for writing expected bus traces."""
    return BusCycle(address, True, data, True)


def write(address: int, data: int) -> BusCycle:
    """A write, for writing expected bus traces."""
    return BusCycle(address, False, data, False)


class CpuError(AssertionError):
    pass


class Mos6502Harness:
    def __init__(self, dut: "DUT"):
        self.dut = dut
        self.memory = bytearray(0x10000)
        self.trace: list[BusCycle] = []
        #: A cycle that `run_until` ran but held back, which the next `cycle()`
        #: call returns instead of running a new one
        self._pending: BusCycle | None = None

    # region Memory

    def load(self, address: int, program: Iterable[int]):
        """Copy bytes into memory, starting at `address`."""
        data = bytes(program)
        self.memory[address : address + len(data)] = data

    def set_vector(self, vector: int, target: int):
        self.memory[vector] = target & 0xFF
        self.memory[vector + 1] = target >> 8

    # endregion

    # region Clocks and pins

    async def start(self):
        """Start the metaclock, with both phases low and every pin idle."""
        dut = self.dut
        dut.phi1.value = 0
        dut.phi2.value = 0
        self._idle_pins()
        cocotb.start_soon(Clock(dut.metaclock, 2, unit="ns").start())
        # The phases change on the metaclock's falling edge, half a cycle away
        # from the rising edge that samples them
        await FallingEdge(dut.metaclock)

    def _idle_pins(self):
        """Set every input pin but the clocks to its idle level. A harness for
        a chip with other pins (like the 2A03, which has no RDY) overrides
        this."""
        dut = self.dut
        dut.reset_pin_n_RES.value = 1
        dut.irq_pin_n_IRQ.value = 1
        dut.nmi_pin_n_NMI.value = 1
        dut.ready_pin_RDY.value = 1
        dut.data_in.value = 0

    async def cycle(self) -> BusCycle:
        """Run one CPU cycle, serving a read or storing a write, and record it."""
        if self._pending is not None:
            bus_cycle, self._pending = self._pending, None
        else:
            bus_cycle = await self._run_cycle()
        self.trace.append(bus_cycle)
        return bus_cycle

    async def _run_cycle(self) -> BusCycle:
        dut = self.dut
        dut.phi1.value = 1
        await ClockCycles(dut.metaclock, METACLOCKS_PER_PHASE, rising=False)
        dut.phi1.value = 0

        address = self._resolve(dut.address.value, "address")
        is_read = bool(self._resolve(dut.read_not_write_R_NOT_W.value, "R/W"))
        sync = bool(self._resolve(dut.sync_SYNC.value, "SYNC"))
        if is_read:
            dut.data_in.value = self.memory[address]

        # Phi2, sampling the data pins just before it ends
        dut.phi2.value = 1
        await ClockCycles(self.dut.metaclock, METACLOCKS_PER_PHASE, rising=False)
        if is_read:
            data = self.memory[address]
        else:
            data = self._resolve(dut.data_out.value, f"data written to {address:04X}")
            self.memory[address] = data
        dut.phi2.value = 0
        return BusCycle(address, is_read, data, sync)

    @staticmethod
    def _resolve(value, name: str) -> int:
        if not value.is_resolvable:
            raise CpuError(f"{name} is {value}")
        return int(value)

    # endregion

    # region Running

    async def cycles(self, count: int) -> list[BusCycle]:
        return [await self.cycle() for _ in range(count)]

    async def reset(self, held_cycles: int = 4) -> list[BusCycle]:
        """Hold /RES low, release it, and run until the reset vector is read.

        Returns the cycles from releasing /RES up to and including the read
        of the vector's high byte, which ends the reset sequence. (SYNC goes
        high during the sequence too, for the BRK it injects, so it can't
        tell where the sequence ends.) The trace is cleared, so it starts at
        the first opcode fetch.
        """
        self._pending = None
        self.dut.reset_pin_n_RES.value = 0
        await self.cycles(held_cycles)
        self.dut.reset_pin_n_RES.value = 1
        self.trace.clear()
        sequence = await self.run_until(
            lambda c: c.read and c.address == RESET_VECTOR + 1, max_cycles=16
        )
        self.trace.clear()
        return sequence

    async def run_until(
        self,
        done: Callable[[BusCycle], bool],
        max_cycles: int = 1000,
        include_last: bool = True,
    ) -> list[BusCycle]:
        """Run cycles until `done` returns True for one of them.

        With `include_last=False`, the matching cycle is still run, but left
        out of the returned list and the trace, and the next `cycle()` call
        returns it instead. That's useful for stopping just before a fetch.
        """
        cycles: list[BusCycle] = []
        for _ in range(max_cycles):
            bus_cycle = await self.cycle()
            if done(bus_cycle):
                if include_last:
                    cycles.append(bus_cycle)
                else:
                    self.trace.pop()
                    self._pending = bus_cycle
                return cycles
            cycles.append(bus_cycle)
        raise CpuError(
            f"Gave up after {max_cycles} cycles. Last cycles:\n" + format_trace(cycles[-16:])
        )

    async def run_until_fetch(self, address: int, max_cycles: int = 1000) -> list[BusCycle]:
        """Run until the opcode at `address` is fetched, and return every cycle
        before that fetch."""
        return await self.run_until(
            lambda c: c.sync and c.address == address, max_cycles, include_last=False
        )

    # endregion


def format_trace(trace: Iterable[BusCycle]) -> str:
    return "\n".join(f"  {i:3}: {c}" for i, c in enumerate(trace))


def assert_trace(actual: list[BusCycle], expected: list[BusCycle]):
    """Compare two bus traces cycle by cycle, showing both on a mismatch."""
    if actual == expected:
        return
    lines = []
    for i in range(max(len(actual), len(expected))):
        a = str(actual[i]) if i < len(actual) else "-"
        e = str(expected[i]) if i < len(expected) else "-"
        marker = "  " if a == e else "!!"
        lines.append(f"  {marker} {i:3}: {a:<18} expected {e}")
    raise AssertionError("Bus trace mismatch:\n" + "\n".join(lines))
