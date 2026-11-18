from typing import TYPE_CHECKING

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Timer
from cocotb.types import LogicArray

if TYPE_CHECKING:
    from program_counter_low import ProgramCounterLow as DUT

#: Metaclock cycles per phase
PHASE = 4


async def setup(dut: "DUT"):
    """Start the metaclock, deassert every control signal, and float the bus."""
    cocotb.start_soon(Clock(dut.metaclock, 1, unit="ns").start())
    dut.phi2.value = 0
    dut.signal_PCL_DB.value = 0
    dut.signal_PCL_ADL.value = 0
    dut.signal_1_PC.value = 0
    dut.signal_PCL_PCL.value = 0
    dut.signal_ADL_PCL.value = 0
    dut.bus_ADL_in.value = LogicArray("ZZZZZZZZ")
    await ClockCycles(dut.metaclock, PHASE)


async def phi2(dut: "DUT"):
    """Run one Phi2, then return to Phi1."""
    dut.phi2.value = 1
    await ClockCycles(dut.metaclock, PHASE)
    dut.phi2.value = 0
    await ClockCycles(dut.metaclock, 1)


async def load_from_adl(dut: "DUT", value: int):
    """Load PCLS from ADL during Phi1, and latch it into PCL during Phi2."""
    dut.bus_ADL_in.value = value
    dut.signal_ADL_PCL.value = 1
    await ClockCycles(dut.metaclock, PHASE)
    dut.signal_ADL_PCL.value = 0
    dut.bus_ADL_in.value = LogicArray("ZZZZZZZZ")
    await phi2(dut)


async def cycle(dut: "DUT", increment: int):
    """Refresh PCLS from PCL during Phi1, and latch PCLS + 1/PC into PCL
    during Phi2."""
    dut.signal_PCL_PCL.value = 1
    dut.signal_1_PC.value = increment
    await ClockCycles(dut.metaclock, PHASE)
    dut.signal_PCL_PCL.value = 0
    await phi2(dut)
    dut.signal_1_PC.value = 0


async def read_db(dut: "DUT") -> int:
    dut.signal_PCL_DB.value = 1
    await Timer(1, unit="ps")
    value = int(dut.bus_DB.value)
    dut.signal_PCL_DB.value = 0
    await Timer(1, unit="ps")
    return value


@cocotb.test()
async def test_program_counter_low_reset(dut: "DUT"):
    """Test that program counter starts at zero after initialization"""
    await setup(dut)
    await phi2(dut)
    assert dut.bus_DB.value == 0xFF, "DB should be released (all ones)"
    assert dut.bus_ADL_out.value == 0xFF, "ADL should be released (all ones)"
    assert await read_db(dut) == 0


@cocotb.test()
async def test_program_counter_increment(dut: "DUT"):
    """1/PC increments PCL by one per cycle, and PCL/PCL alone keeps it."""
    await setup(dut)
    await cycle(dut, increment=0)
    assert await read_db(dut) == 0
    await cycle(dut, increment=1)
    assert await read_db(dut) == 1
    assert dut.signal_PCLC.value == 0, "Expected no carry out"
    await cycle(dut, increment=1)
    assert await read_db(dut) == 2


@cocotb.test()
async def test_program_counter_load_from_adl(dut: "DUT"):
    """Test loading PCL from address low bus"""
    await setup(dut)
    await load_from_adl(dut, 0x42)
    assert await read_db(dut) == 0x42


@cocotb.test()
async def test_program_counter_output_to_buses(dut: "DUT"):
    """Test PCL outputs to both DB and ADL buses"""
    await setup(dut)
    await load_from_adl(dut, 0xA5)
    assert await read_db(dut) == 0xA5

    dut.signal_PCL_ADL.value = 1
    await Timer(1, unit="ps")
    assert dut.bus_ADL_out.value == 0xA5, f"Expected ADL to be 0xA5, got {dut.bus_ADL_out.value}"
    assert dut.bus_DB.value == 0xFF, "DB should be released (all ones)"


@cocotb.test()
async def test_follows_during_phi2(dut: "DUT"):
    """PCL is open during Phi2, so it keeps the value from the end of Phi2,
    and holds while Phi2 is low even if 1/PC changes."""
    await setup(dut)
    await load_from_adl(dut, 0x42)
    dut.signal_1_PC.value = 1
    dut.phi2.value = 1
    await ClockCycles(dut.metaclock, PHASE)
    # 1/PC drops partway through Phi2, and PCL follows it back
    dut.signal_1_PC.value = 0
    await ClockCycles(dut.metaclock, PHASE)
    dut.phi2.value = 0
    await ClockCycles(dut.metaclock, 1)
    assert await read_db(dut) == 0x42

    dut.signal_1_PC.value = 1
    await ClockCycles(dut.metaclock, PHASE)
    assert await read_db(dut) == 0x42
    dut.signal_1_PC.value = 0


@cocotb.test()
async def test_carry_out(dut: "DUT"):
    """Test carry out signal when PCL overflows from 0xFF to 0x00"""
    await setup(dut)
    await load_from_adl(dut, 0xFF)

    dut.signal_PCL_PCL.value = 1
    dut.signal_1_PC.value = 1
    await ClockCycles(dut.metaclock, PHASE)
    assert dut.signal_PCLC.value == 1, "Expected carry out signal to be asserted"
    dut.signal_PCL_PCL.value = 0
    await phi2(dut)
    dut.signal_1_PC.value = 0

    assert await read_db(dut) == 0x00, "Expected PCL to wrap to 0x00"
