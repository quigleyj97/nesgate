from typing import TYPE_CHECKING

import cocotb
from cocotb.clock import Clock
from cocotb.handle import Force, Release
from cocotb.triggers import FallingEdge, RisingEdge, Timer

if TYPE_CHECKING:
    from program_counter_high import ProgramCounterHigh as DUT


async def setup(dut: "DUT"):
    """Start the clocks, deassert every control signal, and float the buses."""
    cocotb.start_soon(Clock(dut.phi2, 10, unit="ns").start())
    cocotb.start_soon(Clock(dut.metaclock, 1, unit="ns").start())
    dut.signal_PCH_DB.value = 0
    dut.signal_PCH_ADH.value = 0
    dut.signal_PCLC.value = 0
    dut.signal_PCH_PCH.value = 0
    dut.signal_ADH_PCH.value = 0
    dut.bus_ADH.value = Release()
    dut.bus_DB.value = Release()
    await Timer(1, unit="ns")


async def load_from_adh(dut: "DUT", value: int):
    """Load PCHS from ADH, and latch it into PCH on the next phi2."""
    await FallingEdge(dut.phi2)
    dut.bus_ADH.value = Force(value)
    dut.signal_ADH_PCH.value = 1
    await RisingEdge(dut.phi2)
    await FallingEdge(dut.phi2)
    dut.signal_ADH_PCH.value = 0
    dut.bus_ADH.value = Release()
    await Timer(1, unit="ns")


async def cycle(dut: "DUT", pclc: int):
    """Refresh PCHS from PCH, and latch PCHS + PCLC into PCH on phi2."""
    dut.signal_PCH_PCH.value = 1
    dut.signal_PCLC.value = pclc
    await RisingEdge(dut.phi2)
    await FallingEdge(dut.phi2)
    dut.signal_PCH_PCH.value = 0
    dut.signal_PCLC.value = 0
    await Timer(1, unit="ns")


async def read_db(dut: "DUT") -> int:
    dut.signal_PCH_DB.value = 1
    await Timer(1, unit="ns")
    value = int(dut.bus_DB.value)
    dut.signal_PCH_DB.value = 0
    await Timer(1, unit="ns")
    return value


@cocotb.test()
async def test_reset(dut: "DUT"):
    """PCH starts at zero, and doesn't drive either bus unless enabled."""
    await setup(dut)
    await RisingEdge(dut.phi2)
    await FallingEdge(dut.phi2)
    assert not dut.bus_DB.value.is_resolvable, "DB should be open"
    assert not dut.bus_ADH.value.is_resolvable, "ADH should be open"
    assert await read_db(dut) == 0


@cocotb.test()
async def test_load_from_adh(dut: "DUT"):
    """ADH/PCH loads PCH from the ADH bus, which can be read back on DB and ADH."""
    await setup(dut)
    await load_from_adh(dut, 0xA5)
    assert await read_db(dut) == 0xA5

    dut.signal_PCH_ADH.value = 1
    await Timer(1, unit="ns")
    assert dut.bus_ADH.value == 0xA5, f"Expected ADH to be 0xA5, got {dut.bus_ADH.value}"
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
        await RisingEdge(dut.phi2)
    await FallingEdge(dut.phi2)
    dut.signal_PCLC.value = 0
    assert await read_db(dut) == 0x43


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
