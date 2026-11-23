from itertools import pairwise
from typing import TYPE_CHECKING, NamedTuple

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

if TYPE_CHECKING:
    from interrupt_controller import InterruptController as DUT

METACLOCKS_PER_PHASE = 4

# Low byte of the vector address, as the precharged ADL bus reads it
NO_VECTOR = 0xFF
BRK_VECTOR = 0xFE
NMI_VECTOR = 0xFA
RESET_VECTOR = 0xFC


class State(NamedTuple):
    RESP: int
    DORES: int
    BRK6E: int
    B_OUT: int
    vector: int


def state(dut: "DUT") -> State:
    pulled = (
        int(dut.clear_0_ADL0.value)
        | int(dut.clear_0_ADL1.value) << 1
        | int(dut.clear_0_ADL2.value) << 2
    )
    return State(
        RESP=int(dut.reset_pending_RESP.value),
        DORES=int(dut.resetting_DORES.value),
        BRK6E=int(dut.brk_cycle_6_end_BRK6E.value),
        B_OUT=int(dut.break_flag_B_OUT.value),
        vector=NO_VECTOR & ~pulled,
    )


IDLE = State(RESP=0, DORES=0, BRK6E=0, B_OUT=1, vector=NO_VECTOR)


class Pins(NamedTuple):
    """Inputs from outside the CPU, which tests hold across several cycles."""

    nmi: int = 1
    irq: int = 1
    res: int = 1
    i_flag: int = 0


NO_PINS = Pins()


async def cycle(
    dut: "DUT",
    pins: Pins = NO_PINS,
    *,
    ready: int = 1,
    t0: int = 0,
    brk_t5: int = 0,
    branch_t2: int = 0,
) -> tuple[State, State]:
    """Run one CPU cycle (Phi1 then Phi2) with the given inputs held throughout.

    Pins are active-low, as on the chip. `ready` is latched during Phi2 by the
    ready controller, so it is applied at Phi2 and holds through the next Phi1.
    Returns the outputs at the end of Phi1 and at the end of Phi2.
    """
    dut.nmi_pin_n_NMI.value = pins.nmi
    dut.irq_pin_n_IRQ.value = pins.irq
    dut.reset_pin_n_RES.value = pins.res
    dut.interrupt_disable_I_OUT.value = pins.i_flag
    dut.cycle_T0.value = t0
    dut.brk_t5_X22.value = brk_t5
    dut.branch_t2_X80.value = branch_t2

    dut.phi1.value = 1
    await ClockCycles(dut.metaclock, METACLOCKS_PER_PHASE)
    dut.phi1.value = 0
    during_phi1 = state(dut)

    dut.ready.value = ready
    dut.phi2.value = 1
    await ClockCycles(dut.metaclock, METACLOCKS_PER_PHASE)
    dut.phi2.value = 0
    during_phi2 = state(dut)
    return during_phi1, during_phi2


async def brk_sequence(
    dut: "DUT", pins: Pins = NO_PINS
) -> dict[str, tuple[State, State]]:
    """Run T0 of an instruction, then the 7-cycle BRK sequence (T1 to T6), then
    T1 of the handler. The decoder's BRK T5 line is set on T5.

    Returns the outputs during each cycle, by name.
    """
    cycles: dict[str, tuple[State, State]] = {}
    cycles["T0"] = await cycle(dut, pins, t0=1)
    for t in range(1, 5):
        cycles[f"T{t}"] = await cycle(dut, pins)
    cycles["T5"] = await cycle(dut, pins, brk_t5=1)
    cycles["T6"] = await cycle(dut, pins)
    cycles["next"] = await cycle(dut, pins)
    return cycles


async def start(dut: "DUT"):
    """Start the metaclock and return every latch to idle.

    Tests share one simulation, so this runs a BRK sequence to finish whatever
    interrupt or reset the last test left pending.
    """
    cocotb.start_soon(Clock(dut.metaclock, 1, unit="ns").start())
    dut.phi1.value = 0
    dut.phi2.value = 0
    dut.ready.value = 1
    for _ in range(3):
        await cycle(dut)
    await brk_sequence(dut)
    for _ in range(2):
        await cycle(dut)
    assert await cycle(dut) == (IDLE, IDLE), "Did not settle while idle"
    assert await cycle(dut, t0=1) == (IDLE, IDLE), "An interrupt was still pending"


def vectors(cycles: dict[str, tuple[State, State]]) -> list[int]:
    """The vector during Phi2 of each cycle, then Phi1 of the next.

    The vector latches open during Phi2, and ADL is read into ABL during Phi1.
    """
    names = list(cycles)
    return [
        v
        for name, after in pairwise(names)
        for v in (cycles[name][1].vector, cycles[after][0].vector)
    ]


def expected_vectors(vector: int) -> list[int]:
    """The vector during Phi2 of each cycle of a BRK sequence, then Phi1 of the
    next, for a sequence fetching the given vector.

    The low byte is pulled down during T5 and T6, and ADL0 only during T5.
    """
    # T0..T4, T5, T6 (Phi2 then the next Phi1)
    return [NO_VECTOR] * 10 + [vector] * 2 + [vector | 1] * 2


@cocotb.test()
async def test_idle(dut: "DUT"):
    """With no interrupts, nothing happens, even at T0"""
    await start(dut)
    for _ in range(3):
        assert await cycle(dut) == (IDLE, IDLE)
    assert await cycle(dut, t0=1) == (IDLE, IDLE)
    assert await cycle(dut, branch_t2=1) == (IDLE, IDLE)


@cocotb.test()
async def test_brk_instruction(dut: "DUT"):
    """BRK on its own reads the IRQ/BRK vector, and keeps B set"""
    await start(dut)

    cycles = await brk_sequence(dut)
    assert vectors(cycles) == expected_vectors(BRK_VECTOR)
    for name, phases in cycles.items():
        for phase in phases:
            assert phase.B_OUT == 1, f"BRK cleared B during {name}"


@cocotb.test()
async def test_brk6e(dut: "DUT"):
    """BRK6E lasts from Phi2 of cycle 6 through Phi1 of cycle 7"""
    await start(dut)

    cycles = await brk_sequence(dut)
    brk6e = [(name, phi1.BRK6E, phi2.BRK6E) for name, (phi1, phi2) in cycles.items()]
    assert brk6e == [
        ("T0", 0, 0),
        ("T1", 0, 0),
        ("T2", 0, 0),
        ("T3", 0, 0),
        ("T4", 0, 0),
        ("T5", 0, 0),
        ("T6", 0, 1),
        ("next", 1, 0),
    ]


@cocotb.test()
async def test_brk6e_stall(dut: "DUT"):
    """While the CPU isn't ready, cycle 6 holds, but BRK6E waits for ready"""
    await start(dut)

    await cycle(dut, t0=1)
    for _ in range(4):
        await cycle(dut)
    await cycle(dut, brk_t5=1)

    # Cycle 6, stalled twice
    for _ in range(2):
        phi1, phi2 = await cycle(dut, ready=0)
        assert (phi1.BRK6E, phi2.BRK6E) == (0, 0), "BRK6E while not ready"

    phi1, phi2 = await cycle(dut)
    assert (phi1.BRK6E, phi2.BRK6E) == (0, 1), "Cycle 6 did not hold through the stall"
    phi1, phi2 = await cycle(dut)
    assert (phi1.BRK6E, phi2.BRK6E) == (1, 0), "BRK6E did not end after cycle 7"


@cocotb.test()
async def test_t5_stall(dut: "DUT"):
    """While the CPU isn't ready, BRK T5 doesn't start the vector fetch"""
    await start(dut)

    await cycle(dut, t0=1)
    for _ in range(4):
        await cycle(dut)
    phi1, phi2 = await cycle(dut, ready=0, brk_t5=1)
    assert (phi1.vector, phi2.vector) == (NO_VECTOR, NO_VECTOR), (
        "Fetched the vector while not ready"
    )

    _, phi2 = await cycle(dut, brk_t5=1)
    assert phi2.vector == BRK_VECTOR, "Did not fetch the vector once ready"
    phi1, phi2 = await cycle(dut)
    assert (phi1.vector, phi2.vector) == (BRK_VECTOR, BRK_VECTOR | 1)
    phi1, phi2 = await cycle(dut)
    assert phi1.vector == BRK_VECTOR | 1
    assert phi2.BRK6E == 0


@cocotb.test()
async def test_reset(dut: "DUT"):
    """Reset sets DORES and clears B, and reads the reset vector"""
    await start(dut)
    pins = Pins(res=0)

    phi1, phi2 = await cycle(dut, pins)
    assert (phi1.RESP, phi2.RESP) == (0, 0), "RESP did not wait for the pad latches"
    phi1, phi2 = await cycle(dut, pins)
    assert phi1.RESP == 1, "RESP was not latched during Phi1"
    assert (phi1.DORES, phi2.DORES) == (0, 1), "DORES was not latched during Phi2"
    assert phi2.B_OUT == 0, "Reset did not clear B"

    # Release reset: DORES holds until the BRK sequence ends
    cycles = await brk_sequence(dut)
    assert vectors(cycles) == expected_vectors(RESET_VECTOR)
    for name in ("T0", "T1", "T2", "T3", "T4", "T5"):
        phi1, phi2 = cycles[name]
        assert (phi1.DORES, phi2.DORES) == (1, 1), f"DORES did not hold during {name}"
        assert (phi1.B_OUT, phi2.B_OUT) == (0, 0), f"B was set during {name}"

    phi1, phi2 = cycles["next"]
    assert (phi1.DORES, phi1.B_OUT) == (0, 1), "BRK6E did not end the reset"
    assert await cycle(dut) == (IDLE, IDLE)


@cocotb.test()
async def test_reset_held(dut: "DUT"):
    """DORES stays set as long as /RES is held low"""
    await start(dut)
    pins = Pins(res=0)

    await cycle(dut, pins)
    await cycle(dut, pins)
    for name, (phi1, phi2) in (await brk_sequence(dut, pins)).items():
        assert (phi1.DORES, phi2.DORES) == (1, 1), f"DORES cleared during {name}"

    await brk_sequence(dut)


@cocotb.test()
async def test_irq(dut: "DUT"):
    """IRQ, while I is clear, clears B at T0, and reads the IRQ/BRK vector"""
    await start(dut)
    pins = Pins(irq=0)

    await cycle(dut, pins)
    cycles = await brk_sequence(dut, pins)
    assert vectors(cycles) == expected_vectors(BRK_VECTOR)

    phi1, phi2 = cycles["T0"]
    assert (phi1.B_OUT, phi2.B_OUT) == (1, 0), "IRQ did not clear B during T0 Phi2"
    for name in ("T1", "T2", "T3", "T4", "T5"):
        phi1, phi2 = cycles[name]
        assert (phi1.B_OUT, phi2.B_OUT) == (0, 0), f"B was set during {name}"
    phi1, phi2 = cycles["T6"]
    assert (phi1.B_OUT, phi2.B_OUT) == (0, 1), "BRK6E did not set B"


@cocotb.test()
async def test_irq_late(dut: "DUT"):
    """IRQ goes through two pad latches, so it must be low before T0"""
    await start(dut)

    phi1, phi2 = await cycle(dut, Pins(irq=0), t0=1)
    assert (phi1.B_OUT, phi2.B_OUT) == (1, 1), "IRQ was not delayed by the pad latches"
    await cycle(dut)


@cocotb.test()
async def test_irq_masked(dut: "DUT"):
    """IRQ is ignored while the I flag is set"""
    await start(dut)
    pins = Pins(irq=0, i_flag=1)

    await cycle(dut, pins)
    cycles = await brk_sequence(dut, pins)
    for name, phases in cycles.items():
        for phase in phases:
            assert phase.B_OUT == 1, f"Masked IRQ cleared B during {name}"


@cocotb.test()
async def test_interrupt_check_cycles(dut: "DUT"):
    """Interrupts are only checked during T0, or T2 of a branch"""
    await start(dut)
    pins = Pins(irq=0)

    for _ in range(3):
        _, phi2 = await cycle(dut, pins)
        assert phi2.B_OUT == 1, "IRQ was checked outside T0 and BR2"

    _, phi2 = await cycle(dut, pins, branch_t2=1)
    assert phi2.B_OUT == 0, "IRQ was not checked during BR2"

    # B stays clear, even after IRQ is released, until the BRK sequence ends
    for _ in range(3):
        _, phi2 = await cycle(dut)
        assert phi2.B_OUT == 0, "B was set without BRK6E"
    await brk_sequence(dut)


@cocotb.test()
async def test_nmi(dut: "DUT"):
    """NMI clears B at T0, and reads the NMI vector"""
    await start(dut)
    pins = Pins(nmi=0)

    await cycle(dut, pins)
    await cycle(dut, pins)
    cycles = await brk_sequence(dut, pins)
    assert vectors(cycles) == expected_vectors(NMI_VECTOR)

    phi1, phi2 = cycles["T0"]
    assert (phi1.B_OUT, phi2.B_OUT) == (1, 0), "NMI did not clear B during T0 Phi2"
    phi1, phi2 = cycles["T6"]
    assert (phi1.B_OUT, phi2.B_OUT) == (0, 1), "BRK6E did not set B"


@cocotb.test()
async def test_nmi_ignores_i_flag(dut: "DUT"):
    """NMI can't be masked by the I flag"""
    await start(dut)
    pins = Pins(nmi=0, i_flag=1)

    await cycle(dut, pins)
    await cycle(dut, pins)
    cycles = await brk_sequence(dut, pins)
    assert cycles["T0"][1].B_OUT == 0, "The I flag masked NMI"
    assert vectors(cycles) == expected_vectors(NMI_VECTOR)


@cocotb.test()
async def test_nmi_edge_triggered(dut: "DUT"):
    """Holding /NMI low only takes one NMI. It must go high to trigger again."""
    await start(dut)
    pins = Pins(nmi=0)

    await cycle(dut, pins)
    await cycle(dut, pins)
    assert vectors(await brk_sequence(dut, pins)) == expected_vectors(NMI_VECTOR)

    cycles = await brk_sequence(dut, pins)
    assert cycles["T0"][1].B_OUT == 1, "A held /NMI triggered again"
    assert vectors(cycles) == expected_vectors(BRK_VECTOR)

    await cycle(dut)
    await cycle(dut)
    await cycle(dut, pins)
    await cycle(dut, pins)
    cycles = await brk_sequence(dut, pins)
    assert cycles["T0"][1].B_OUT == 0, "A new falling edge did not trigger"
    assert vectors(cycles) == expected_vectors(NMI_VECTOR)


@cocotb.test()
async def test_nmi_pulse(dut: "DUT"):
    """A short /NMI pulse is remembered until the next T0"""
    await start(dut)

    await cycle(dut, Pins(nmi=0))
    await cycle(dut, Pins(nmi=0))
    for _ in range(3):
        await cycle(dut)
    cycles = await brk_sequence(dut)
    assert cycles["T0"][1].B_OUT == 0, "The NMI pulse was forgotten"
    assert vectors(cycles) == expected_vectors(NMI_VECTOR)


async def brk_with_nmi_from(dut: "DUT", first_low: int) -> list[int]:
    """Run a BRK sequence with /NMI going low from cycle `first_low` (1-6).

    Returns the vectors from T4 Phi2 to the Phi1 after T6.
    """
    await cycle(dut, t0=1)
    observed: list[int] = []
    for t in range(1, 8):
        pins = Pins(nmi=0 if t >= first_low else 1)
        phi1, phi2 = await cycle(dut, pins, brk_t5=int(t == 5))
        if t >= 5:
            observed.append(phi1.vector)
        if 4 <= t <= 6:
            observed.append(phi2.vector)
    return observed


@cocotb.test()
async def test_nmi_hijacks_brk(dut: "DUT"):
    """An NMI that falls before BRK T5 hijacks BRK's vector fetch.

    BRK still keeps B set, and the NMI isn't taken again afterwards.
    """
    await start(dut)

    observed = await brk_with_nmi_from(dut, 4)
    assert observed == [NO_VECTOR] * 2 + [NMI_VECTOR] * 2 + [NMI_VECTOR | 1] * 2, (
        "The NMI did not hijack the vector fetch"
    )

    cycles = await brk_sequence(dut, Pins(nmi=0))
    assert cycles["T0"][1].B_OUT == 1, "The hijacking NMI was taken again"
    assert vectors(cycles) == expected_vectors(BRK_VECTOR)


@cocotb.test()
async def test_nmi_during_vector_fetch(dut: "DUT"):
    """An NMI that falls while BRK fetches its vector is taken afterwards"""
    await start(dut)

    observed = await brk_with_nmi_from(dut, 5)
    assert observed == [NO_VECTOR] * 2 + [BRK_VECTOR] * 2 + [BRK_VECTOR | 1] * 2, (
        "The NMI hijacked the vector fetch"
    )

    cycles = await brk_sequence(dut, Pins(nmi=0))
    assert cycles["T0"][1].B_OUT == 0, "The NMI was lost"
    assert vectors(cycles) == expected_vectors(NMI_VECTOR)


@cocotb.test()
async def test_reset_overrides_nmi(dut: "DUT"):
    """During reset, the reset vector wins over a pending NMI"""
    await start(dut)
    pins = Pins(nmi=0, res=0)

    await cycle(dut, pins)
    await cycle(dut, pins)
    cycles = await brk_sequence(dut, Pins(nmi=0))
    assert vectors(cycles) == expected_vectors(RESET_VECTOR)
