from typing import TYPE_CHECKING, NamedTuple

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

if TYPE_CHECKING:
    from ready_controller import ReadyController as DUT

METACLOCKS_PER_PHASE = 4

WRITE_SOURCES = {
    "STOR": "store_cycle_STOR",
    "PC/DB": "pc_to_db_PC_DB",
    "X98": "brk_t4_X98",
    "X100": "push_t2_X100",
    "T6": "rmw_cycle_T6",
    "T7": "rmw_cycle_T7",
}


class State(NamedTuple):
    ready: int
    WR: int
    ReadyPhi1: int
    PRDY: int
    R_NOT_W: int


def state(dut: "DUT") -> State:
    return State(
        ready=int(dut.ready.value),
        WR=int(dut.write_cycle_WR.value),
        ReadyPhi1=int(dut.ready_phi1_ReadyPhi1.value),
        PRDY=int(dut.previous_ready_PRDY.value),
        R_NOT_W=int(dut.read_not_write_R_NOT_W.value),
    )


IDLE = State(ready=1, WR=0, ReadyPhi1=1, PRDY=1, R_NOT_W=1)


async def cycle(
    dut: "DUT", *, rdy: int = 1, writes: frozenset[str] = frozenset(), dores: int = 0
) -> tuple[State, State]:
    """Run one CPU cycle (Phi1 then Phi2) with the given inputs held throughout.

    Returns the outputs at the end of Phi1 and at the end of Phi2.
    """
    dut.ready_pin_RDY.value = rdy
    dut.resetting_DORES.value = dores
    for name, port in WRITE_SOURCES.items():
        getattr(dut, port).value = int(name in writes)

    dut.phi1.value = 1
    await ClockCycles(dut.metaclock, METACLOCKS_PER_PHASE)
    dut.phi1.value = 0
    during_phi1 = state(dut)

    dut.phi2.value = 1
    await ClockCycles(dut.metaclock, METACLOCKS_PER_PHASE)
    dut.phi2.value = 0
    during_phi2 = state(dut)
    return during_phi1, during_phi2


async def start(dut: "DUT"):
    """Start the metaclock and run idle cycles until every latch is back to idle.

    Tests share one simulation, so this flushes whatever the last test left.
    """
    cocotb.start_soon(Clock(dut.metaclock, 1, unit="ns").start())
    dut.phi1.value = 0
    dut.phi2.value = 0
    for _ in range(3):
        await cycle(dut)
    assert await cycle(dut) == (IDLE, IDLE), "Did not settle while idle"


@cocotb.test()
async def test_idle(dut: "DUT"):
    """With RDY high and no writes, the CPU is ready and reading"""
    await start(dut)
    for _ in range(3):
        assert await cycle(dut) == (IDLE, IDLE)


@cocotb.test()
async def test_stall_on_read(dut: "DUT"):
    """RDY is latched during Phi2, so a stall holds from Phi2 through Phi1"""
    await start(dut)

    phi1, phi2 = await cycle(dut, rdy=0)
    assert phi1.ready == 1, "RDY took effect during Phi1"
    assert phi2.ready == 0, "Low RDY did not stall during Phi2"

    phi1, phi2 = await cycle(dut)
    assert phi1.ready == 0, "The stall did not hold through Phi1"
    assert phi2.ready == 1, "High RDY did not resume during Phi2"

    for phi in await cycle(dut):
        assert phi.ready == 1


@cocotb.test()
async def test_ready_phi1(dut: "DUT"):
    """ReadyPhi1 is ready during Phi1, so it lags ready by one phase"""
    await start(dut)

    phi1, phi2 = await cycle(dut, rdy=0)
    assert (phi1.ReadyPhi1, phi2.ReadyPhi1) == (1, 1), "ReadyPhi1 fell with ready"
    phi1, phi2 = await cycle(dut)
    assert phi1.ReadyPhi1 == 1, "ReadyPhi1 fell before Phi2"
    assert phi2.ReadyPhi1 == 0, "ReadyPhi1 did not follow ready from Phi1"
    phi1, phi2 = await cycle(dut)
    assert (phi1.ReadyPhi1, phi2.ReadyPhi1) == (0, 1), (
        "ReadyPhi1 did not follow ready from Phi1"
    )


@cocotb.test()
async def test_previous_ready(dut: "DUT"):
    """PRDY is the RDY pin latched during Phi2 and then Phi1"""
    await start(dut)

    phi1, phi2 = await cycle(dut, rdy=0)
    assert (phi1.PRDY, phi2.PRDY) == (1, 1), "PRDY fell before the next Phi1"
    phi1, phi2 = await cycle(dut)
    assert (phi1.PRDY, phi2.PRDY) == (0, 0), "PRDY did not follow RDY from Phi2"
    phi1, phi2 = await cycle(dut)
    assert (phi1.PRDY, phi2.PRDY) == (1, 1), "PRDY did not recover"


@cocotb.test()
async def test_write_sources(dut: "DUT"):
    """Each write source sets WR from Phi2 through the next Phi1"""
    await start(dut)

    for name in WRITE_SOURCES:
        phi1, phi2 = await cycle(dut, writes=frozenset({name}))
        assert phi1.WR == 0, f"{name} set WR before Phi2"
        assert phi2.WR == 1, f"{name} did not set WR"
        phi1, phi2 = await cycle(dut)
        assert phi1.WR == 1, f"WR from {name} did not hold through Phi1"
        assert phi2.WR == 0, f"WR from {name} did not clear"


@cocotb.test()
async def test_no_stall_on_write(dut: "DUT"):
    """Low RDY doesn't stall a write cycle, only the read cycle after it"""
    await start(dut)

    assert (await cycle(dut, writes=frozenset({"STOR"})))[1].WR == 1
    _, phi2 = await cycle(dut, rdy=0)
    assert phi2.ready == 1, "Stalled during a write cycle"
    _, phi2 = await cycle(dut, rdy=0)
    assert phi2.ready == 0, "Did not stall on the read cycle after the write"
    await cycle(dut)


@cocotb.test()
async def test_stalled_cycle_does_not_write(dut: "DUT"):
    """WR needs ready, so a stalled cycle doesn't write"""
    await start(dut)

    _, phi2 = await cycle(dut, rdy=0, writes=frozenset({"STOR"}))
    assert (phi2.ready, phi2.WR) == (0, 0), "Wrote while stalled"
    _, phi2 = await cycle(dut, writes=frozenset({"STOR"}))
    assert (phi2.ready, phi2.WR) == (1, 1), "Did not write once ready"
    await cycle(dut)


@cocotb.test()
async def test_dores_blocks_writes(dut: "DUT"):
    """During reset (DORES) the CPU never writes, so it can stall on any cycle"""
    await start(dut)

    _, phi2 = await cycle(dut, writes=frozenset(WRITE_SOURCES), dores=1)
    assert phi2.WR == 0, "Wrote during reset"
    _, phi2 = await cycle(dut, rdy=0, dores=1)
    assert phi2.ready == 0, "Did not stall during reset"
    await cycle(dut)


@cocotb.test()
async def test_read_not_write_pin(dut: "DUT"):
    """The R/W pin latches WR during Phi1, so it's low for the whole write cycle"""
    await start(dut)

    phi1, phi2 = await cycle(dut, writes=frozenset({"STOR"}))
    assert (phi1.R_NOT_W, phi2.R_NOT_W) == (1, 1), "R/W fell before the write cycle"
    phi1, phi2 = await cycle(dut)
    assert (phi1.R_NOT_W, phi2.R_NOT_W) == (0, 0), "R/W did not stay low through the write cycle"
    phi1, phi2 = await cycle(dut)
    assert (phi1.R_NOT_W, phi2.R_NOT_W) == (1, 1), "R/W did not go back to read"
