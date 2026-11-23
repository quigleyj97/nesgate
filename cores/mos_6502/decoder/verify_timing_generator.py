from typing import TYPE_CHECKING

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

if TYPE_CHECKING:
    from timing_generator import TimingGenerator as DUT

METACLOCKS_PER_PHASE = 4

OUTPUTS = {
    "T0": "cycle_T0",
    "T1": "cycle_T1",
    "T1X": "cycle_T1X",
    "T2": "cycle_T2",
    "T3": "cycle_T3",
    "T4": "cycle_T4",
    "T5": "cycle_T5",
    "T6": "rmw_cycle_T6",
    "T7": "rmw_cycle_T7",
}


def active(dut: "DUT") -> set[str]:
    """The names of every timing signal that's currently asserted"""
    return {name for name, port in OUTPUTS.items() if getattr(dut, port).value == 1}


async def start(dut: "DUT"):
    """Start the metaclock and run idle cycles until every counter is clear.

    Like the real chip, the counters have no reset of their own. Tests share
    one simulation, so this flushes whatever the last test left behind.
    """
    cocotb.start_soon(Clock(dut.metaclock, 1, unit="ns").start())
    dut.phi1.value = 0
    dut.phi2.value = 0
    dut.ready.value = 1
    dut.reset_short_counter_TRES1.value = 0
    dut.reset_counters_TRESX.value = 0
    dut.short_instruction_TWOCYCLE.value = 0
    dut.shift_instruction_SHIFT.value = 0
    dut.memory_operation_MemOP.value = 0
    await ClockCycles(dut.metaclock, 2)

    # T5 takes the longest to drain, shifting out from T2
    for _ in range(5):
        await cycle(dut)
    assert active(dut) == set(), "Counters did not clear while idle"


async def cycle(
    dut: "DUT",
    *,
    tres1: int = 0,
    tresx: int = 0,
    twocycle: int = 0,
    shift: int = 0,
    memop: int = 0,
    ready_next: bool = True,
) -> set[str]:
    """Run one CPU cycle (Phi1 then Phi2), and return the active timing signals.

    The real chip latches `/ready` during Phi2, so it holds from Phi2 through
    the next Phi1. `ready_next=False` models that: it drops `ready` during this
    cycle's Phi2, which stalls the next cycle, and the next call raises it
    again during Phi2 unless it stalls too.
    """
    dut.reset_short_counter_TRES1.value = tres1
    dut.reset_counters_TRESX.value = tresx
    dut.short_instruction_TWOCYCLE.value = twocycle
    dut.shift_instruction_SHIFT.value = shift
    dut.memory_operation_MemOP.value = memop

    dut.phi1.value = 1
    await ClockCycles(dut.metaclock, METACLOCKS_PER_PHASE)
    during_phi1 = active(dut)
    dut.phi1.value = 0

    dut.ready.value = int(ready_next)
    dut.phi2.value = 1
    await ClockCycles(dut.metaclock, METACLOCKS_PER_PHASE)
    dut.phi2.value = 0
    during_phi2 = active(dut)

    assert during_phi1 == during_phi2, (
        f"Timing changed during Phi2: {sorted(during_phi1)} -> {sorted(during_phi2)}"
    )
    return during_phi1


@cocotb.test()
async def test_idle(dut: "DUT"):
    """Without TRES1 or TRESX, no cycle is ever active"""
    await start(dut)
    for _ in range(4):
        assert await cycle(dut) == set()


@cocotb.test()
async def test_two_cycle_instruction(dut: "DUT"):
    """A 2-cycle instruction (e.g. LDA #) overlaps T0 with T2"""
    await start(dut)

    assert await cycle(dut, tres1=1) == {"T1"}, "Opcode fetch"
    assert await cycle(dut, twocycle=1) == {"T0", "T2"}, "TWOCYCLE did not start T0"
    # Fetching the next opcode. The predecode register now holds the operand
    # byte, whose TWOCYCLE is masked by T1. TRES2 clears T3.
    assert await cycle(dut, tres1=1, tresx=1, twocycle=1) == {"T1", "T1X"}, (
        "T1X did not follow T0"
    )
    assert await cycle(dut) == {"T2"}, "Next instruction did not continue to T2"


@cocotb.test()
async def test_long_instruction(dut: "DUT"):
    """A 4-cycle instruction (e.g. LDA abs) finishes on T0 after T3"""
    await start(dut)

    assert await cycle(dut, tres1=1) == {"T1"}
    assert await cycle(dut) == {"T2"}
    assert await cycle(dut) == {"T3"}
    # TRESX starts T0, and TRES2 clears T4
    assert await cycle(dut, tresx=1) == {"T0"}, "TRESX did not end the instruction"
    assert await cycle(dut, tres1=1) == {"T1", "T1X"}
    assert await cycle(dut) == {"T2"}


@cocotb.test()
async def test_extended_counter_shift(dut: "DUT"):
    """T1 shifts through T2-T5 one cycle at a time, then falls off the end"""
    await start(dut)

    assert await cycle(dut, tres1=1) == {"T1"}
    for name in ("T2", "T3", "T4", "T5"):
        assert await cycle(dut) == {name}, f"Did not shift into {name}"
    assert await cycle(dut) == set(), "Did not shift out of T5"


@cocotb.test()
async def test_tres2_clears_extended_counter(dut: "DUT"):
    """TRES2 clears T2-T5 even while the CPU is stalled"""
    await start(dut)

    assert await cycle(dut, tres1=1) == {"T1"}
    assert await cycle(dut, ready_next=False) == {"T2"}
    assert await cycle(dut, tresx=1) == {"T0"}, "TRES2 did not clear T2 while stalled"
    assert await cycle(dut) == {"T1X"}, "T2 came back after TRES2"


@cocotb.test()
async def test_not_ready_extended_counter(dut: "DUT"):
    """While not ready, T2-T5 hold the current cycle"""
    await start(dut)

    assert await cycle(dut, tres1=1) == {"T1"}
    assert await cycle(dut) == {"T2"}
    assert await cycle(dut, ready_next=False) == {"T3"}
    assert await cycle(dut, ready_next=False) == {"T3"}, "T3 did not hold while stalled"
    assert await cycle(dut) == {"T3"}, "T3 did not hold while stalled"
    assert await cycle(dut) == {"T4"}, "Did not continue once ready"


@cocotb.test()
async def test_not_ready_short_counter(dut: "DUT"):
    """While not ready, T0 holds and T1X waits for it to finish"""
    await start(dut)

    assert await cycle(dut, tres1=1) == {"T1"}
    assert await cycle(dut, twocycle=1, ready_next=False) == {"T0", "T2"}
    # The dispatch logic holds off TRES1 while stalled
    assert await cycle(dut) == {"T0", "T2"}, "T0 did not hold while stalled"
    assert await cycle(dut, tres1=1, tresx=1) == {"T1", "T1X"}, (
        "T1X did not follow T0 once ready"
    )
    assert await cycle(dut) == {"T2"}


@cocotb.test()
async def test_rmw_counter(dut: "DUT"):
    """SHIFT and MemOP together start T6, and T7 follows it"""
    await start(dut)

    assert await cycle(dut, shift=1) == set()
    assert await cycle(dut, memop=1) == set(), "SHIFT alone started T6"
    assert await cycle(dut, shift=1, memop=1) == set(), "MemOP alone started T6"
    assert await cycle(dut) == {"T6"}, "SHIFT and MemOP did not start T6"
    assert await cycle(dut) == {"T7"}, "T7 did not follow T6"
    assert await cycle(dut) == set(), "T7 did not end"


@cocotb.test()
async def test_not_ready_rmw_counter(dut: "DUT"):
    """While not ready, T6 doesn't start or end, and T7 waits for it"""
    await start(dut)

    # Stalling repeats the SHIFT and MemOP cycle, so T6 starts one cycle later
    assert await cycle(dut, shift=1, memop=1, ready_next=False) == set()
    assert await cycle(dut, shift=1, memop=1) == set(), "T6 started while stalled"
    assert await cycle(dut, ready_next=False) == {"T6"}
    assert await cycle(dut, ready_next=False) == {"T6"}, "T6 did not hold while stalled"
    assert await cycle(dut) == {"T6"}, "T6 did not hold while stalled"
    assert await cycle(dut) == {"T7"}, "T7 did not follow T6 once ready"
    assert await cycle(dut) == set()
