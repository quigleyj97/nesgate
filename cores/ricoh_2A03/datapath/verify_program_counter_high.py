from typing import TYPE_CHECKING

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Timer
from cocotb.types import LogicArray

if TYPE_CHECKING:
    from program_counter_high import ProgramCounterHigh as DUT

#: Metaclock cycles per phase
PHASE = 4


async def setup(dut: "DUT"):
    """Start the metaclock, deassert every control signal, and float the buses."""
    cocotb.start_soon(Clock(dut.metaclock, 1, unit="ns").start())
    dut.phi2.value = 0
    dut.signal_PCH_DB.value = 0
    dut.signal_PCH_ADH.value = 0
    dut.signal_PCLC.value = 0
    dut.signal_PCH_PCH.value = 0
    dut.signal_ADH_PCH.value = 0
    dut.bus_ADH_in.value = LogicArray("ZZZZZZZZ")
    await ClockCycles(dut.metaclock, PHASE)


async def phi2(dut: "DUT"):
    """Run one Phi2, then return to Phi1."""
    dut.phi2.value = 1
    await ClockCycles(dut.metaclock, PHASE)
    dut.phi2.value = 0
    await ClockCycles(dut.metaclock, 1)


async def load_from_adh(dut: "DUT", value: int):
    """Load PCHS from ADH during Phi1, and latch it into PCH during Phi2."""
    dut.bus_ADH_in.value = value
    dut.signal_ADH_PCH.value = 1
    await ClockCycles(dut.metaclock, PHASE)
    dut.signal_ADH_PCH.value = 0
    dut.bus_ADH_in.value = LogicArray("ZZZZZZZZ")
    await phi2(dut)


async def cycle(dut: "DUT", pclc: int):
    """Refresh PCHS from PCH during Phi1, and latch PCHS + PCLC into PCH
    during Phi2."""
    dut.signal_PCH_PCH.value = 1
    dut.signal_PCLC.value = pclc
    await ClockCycles(dut.metaclock, PHASE)
    dut.signal_PCH_PCH.value = 0
    await phi2(dut)
    dut.signal_PCLC.value = 0


async def read_db(dut: "DUT") -> int:
    dut.signal_PCH_DB.value = 1
    await Timer(1, unit="ps")
    value = int(dut.bus_DB.value)
    dut.signal_PCH_DB.value = 0
    await Timer(1, unit="ps")
    return value


@cocotb.test()
async def test_reset(dut: "DUT"):
    """PCH starts at zero, and doesn't drive either bus unless enabled."""
    await setup(dut)
    await phi2(dut)
    assert not dut.bus_DB.value.is_resolvable, "DB should be open"
    assert not dut.bus_ADH_out.value.is_resolvable, "ADH should be open"
    assert await read_db(dut) == 0


@cocotb.test()
async def test_load_from_adh(dut: "DUT"):
    """ADH/PCH loads PCH from the ADH bus, which can be read back on DB and ADH."""
    await setup(dut)
    await load_from_adh(dut, 0xA5)
    assert await read_db(dut) == 0xA5

    dut.signal_PCH_ADH.value = 1
    await Timer(1, unit="ps")
    assert dut.bus_ADH_out.value == 0xA5, f"Expected ADH to be 0xA5, got {dut.bus_ADH_out.value}"
    assert not dut.bus_DB.value.is_resolvable, "DB should be open"


@cocotb.test()
async def test_hold_without_carry(dut: "DUT"):
    """Without a carry from PCL, PCH/PCH keeps the current value."""
    await setup(dut)
    await load_from_adh(dut, 0x42)
    for _ in range(3):
        await cycle(dut, pclc=0)
    assert await read_db(dut) == 0x42


@cocotb.test()
async def test_increment_on_pclc(dut: "DUT"):
    """PCLC increments PCH by one per cycle."""
    await setup(dut)
    await load_from_adh(dut, 0x42)
    await cycle(dut, pclc=1)
    assert await read_db(dut) == 0x43
    await cycle(dut, pclc=1)
    assert await read_db(dut) == 0x44


@cocotb.test()
async def test_increment_without_refresh(dut: "DUT"):
    """PCH latches PCHS + PCLC, so without PCH/PCH it doesn't keep counting."""
    await setup(dut)
    await load_from_adh(dut, 0x42)
    await cycle(dut, pclc=0)
    dut.signal_PCLC.value = 1
    for _ in range(3):
        await phi2(dut)
    dut.signal_PCLC.value = 0
    assert await read_db(dut) == 0x43


@cocotb.test()
async def test_follows_during_phi2(dut: "DUT"):
    """PCH is open during Phi2, so it keeps the value from the end of Phi2,
    and holds while Phi2 is low even if PCLC changes."""
    await setup(dut)
    await load_from_adh(dut, 0x42)
    dut.signal_PCLC.value = 1
    dut.phi2.value = 1
    await ClockCycles(dut.metaclock, PHASE)
    # PCLC drops partway through Phi2, and PCH follows it back
    dut.signal_PCLC.value = 0
    await ClockCycles(dut.metaclock, PHASE)
    dut.phi2.value = 0
    await ClockCycles(dut.metaclock, 1)
    assert await read_db(dut) == 0x42

    dut.signal_PCLC.value = 1
    await ClockCycles(dut.metaclock, PHASE)
    assert await read_db(dut) == 0x42
    dut.signal_PCLC.value = 0


@cocotb.test()
async def test_nibble_carry(dut: "DUT"):
    """The low nibble carries into the high nibble (PCHC)."""
    await setup(dut)
    await load_from_adh(dut, 0x0F)
    await cycle(dut, pclc=1)
    assert await read_db(dut) == 0x10

    await load_from_adh(dut, 0x7F)
    await cycle(dut, pclc=1)
    assert await read_db(dut) == 0x80


@cocotb.test()
async def test_wrap(dut: "DUT"):
    """PCH wraps from 0xFF to 0x00."""
    await setup(dut)
    await load_from_adh(dut, 0xFF)
    await cycle(dut, pclc=1)
    assert await read_db(dut) == 0x00
