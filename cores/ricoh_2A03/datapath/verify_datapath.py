from typing import TYPE_CHECKING

"""Smoke tests for the datapath core.

These check the wiring between the subunits rather than re-testing each one,
in particular that several of them can share a bus: each releases it to 'Z'
when it isn't enabled, and the bus resolves to whichever one is driving.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.handle import Force, Release
from cocotb.triggers import Timer

if TYPE_CHECKING:
    from mos_6502_datapath import Mos6502Datapath as DUT

CONTROL_SIGNALS = [
    "phi1",
    "phi2",
    "load_SB_AC",
    "output_enable_AC_SB",
    "output_enable_AC_DB",
    "load_SB_X",
    "output_enable_X_SB",
    "load_SB_Y",
    "output_enable_Y_SB",
    "load_ADH_ABH",
    "load_ADL_ABL",
    "load_PCL_PCL",
    "load_ADL_PCL",
    "signal_I_PC",
    "output_enable_PCL_DB",
    "output_enable_PCL_ADL",
    "load_PCH_PCH",
    "load_ADH_PCH",
    "output_enable_PCH_DB",
    "output_enable_PCH_ADH",
    "output_enable_DL_DB",
    "output_enable_DL_ADL",
    "output_enable_DL_ADH",
    "signal_R_NOT_W",
    "output_enable_P_DB",
    "signal_IR5",
    "signal_ACR",
    "signal_AVR",
    "signal_DB0_C",
    "signal_IR5_C",
    "signal_ACR_C",
    "signal_DB1_Z",
    "signal_DBZ_Z",
    "signal_DB2_I",
    "signal_IR5_I",
    "signal_DB3_D",
    "signal_IR5_D",
    "signal_DB6_V",
    "signal_AVR_V",
    "signal_1_V",
    "signal_DB7_N",
]

BUSES = ["databus_SB", "databus_DB", "databus_ADH", "databus_ADL"]


async def reset(dut: "DUT"):
    """Start the metaclock, deassert every control signal, and stop driving the buses."""
    cocotb.start_soon(Clock(dut.metaclock, 1, unit="ns").start())
    for name in CONTROL_SIGNALS:
        getattr(dut, name).value = 0
    # Read mode, so the data output latch doesn't drive the data pins
    dut.signal_R_NOT_W.value = 1
    for name in BUSES:
        getattr(dut, name).value = Release()
    await Timer(1, unit="ns")


async def pulse(signal):
    signal.value = 1
    await Timer(1, unit="ns")
    signal.value = 0
    await Timer(1, unit="ns")


async def phase(clock):
    """Run one clock phase, long enough for several metaclock edges."""
    clock.value = 1
    await Timer(4, unit="ns")
    clock.value = 0
    await Timer(1, unit="ns")


async def read_pc(dut: "DUT") -> tuple[int, int]:
    """Read the program counter from ADH/ADL, and again from DB a byte at a time."""
    dut.output_enable_PCL_ADL.value = 1
    dut.output_enable_PCH_ADH.value = 1
    await Timer(1, unit="ns")
    from_address_buses = (int(dut.databus_ADH.value) << 8) | int(dut.databus_ADL.value)
    dut.output_enable_PCL_ADL.value = 0
    dut.output_enable_PCH_ADH.value = 0

    dut.output_enable_PCL_DB.value = 1
    await Timer(1, unit="ns")
    low = int(dut.databus_DB.value)
    dut.output_enable_PCL_DB.value = 0
    dut.output_enable_PCH_DB.value = 1
    await Timer(1, unit="ns")
    high = int(dut.databus_DB.value)
    dut.output_enable_PCH_DB.value = 0
    await Timer(1, unit="ns")
    return from_address_buses, (high << 8) | low


async def load_pc(dut: "DUT", value: int):
    """Load the program counter from ADH/ADL during phi1, and latch it on phi2."""
    dut.databus_ADH.value = Force(value >> 8)
    dut.databus_ADL.value = Force(value & 0xFF)
    dut.load_ADH_PCH.value = 1
    dut.load_ADL_PCL.value = 1
    await Timer(1, unit="ns")
    await phase(dut.phi1)
    dut.load_ADH_PCH.value = 0
    dut.load_ADL_PCL.value = 0
    dut.databus_ADH.value = Release()
    dut.databus_ADL.value = Release()
    await phase(dut.phi2)


async def increment_pc(dut: "DUT"):
    """Refresh the PC select registers during phi1, and increment on phi2."""
    dut.load_PCH_PCH.value = 1
    dut.load_PCL_PCL.value = 1
    dut.signal_I_PC.value = 1
    await phase(dut.phi1)
    dut.load_PCH_PCH.value = 0
    dut.load_PCL_PCL.value = 0
    await phase(dut.phi2)
    dut.signal_I_PC.value = 0


async def load_from_sb(dut: "DUT", load, value: int):
    """Drive SB from outside the core, and pulse a register's load signal."""
    dut.databus_SB.value = Force(value)
    await Timer(1, unit="ns")
    await pulse(load)
    dut.databus_SB.value = Release()
    await Timer(1, unit="ns")


@cocotb.test()
async def test_buses_float_when_idle(dut: "DUT"):
    """With nothing enabled, no subunit drives any of the internal buses."""
    await reset(dut)
    for name in BUSES:
        assert not getattr(dut, name).value.is_resolvable, f"{name} should be open"


@cocotb.test()
async def test_registers_share_sb(dut: "DUT"):
    """X, Y and AC all sit on SB, and only the enabled one drives it."""
    await reset(dut)
    await load_from_sb(dut, dut.load_SB_X, 0x5A)
    await load_from_sb(dut, dut.load_SB_Y, 0xA5)
    await load_from_sb(dut, dut.load_SB_AC, 0x3C)

    for enable, expected in [
        (dut.output_enable_X_SB, 0x5A),
        (dut.output_enable_Y_SB, 0xA5),
        (dut.output_enable_AC_SB, 0x3C),
    ]:
        enable.value = 1
        await Timer(1, unit="ns")
        assert dut.databus_SB.value == expected, f"SB should be {expected:#04x}, got {dut.databus_SB.value}"
        enable.value = 0
        await Timer(1, unit="ns")
        assert not dut.databus_SB.value.is_resolvable, "SB should be open again"


@cocotb.test()
async def test_accumulator_to_db(dut: "DUT"):
    """The accumulator can drive DB, which the status register also sits on."""
    await reset(dut)
    await load_from_sb(dut, dut.load_SB_AC, 0xC3)
    dut.output_enable_AC_DB.value = 1
    await Timer(1, unit="ns")
    assert dut.databus_DB.value == 0xC3


@cocotb.test()
async def test_address_registers(dut: "DUT"):
    """ABH and ABL load from ADH and ADL during phi1, and drive the address pins."""
    await reset(dut)
    dut.databus_ADH.value = Force(0x12)
    dut.databus_ADL.value = Force(0x34)
    dut.load_ADH_ABH.value = 1
    dut.load_ADL_ABL.value = 1
    await Timer(1, unit="ns")
    await pulse(dut.phi1)
    dut.load_ADH_ABH.value = 0
    dut.load_ADL_ABL.value = 0
    dut.databus_ADH.value = Release()
    dut.databus_ADL.value = Release()
    await Timer(1, unit="ns")
    assert dut.address.value == 0x1234, f"Expected address 0x1234, got {dut.address.value}"

    # The address registers hold their value without a phi1 load
    dut.databus_ADH.value = Force(0xFF)
    dut.databus_ADL.value = Force(0xFF)
    await pulse(dut.phi1)
    assert dut.address.value == 0x1234, "Address registers should not load without ADH/ABH and ADL/ABL"


@cocotb.test()
async def test_data_input_latch(dut: "DUT"):
    """The data input latch loads from the data pins on phi2, and drives DB and ADL."""
    await reset(dut)
    dut.data.value = Force(0x77)
    await Timer(1, unit="ns")
    await pulse(dut.phi2)
    dut.data.value = Release()

    dut.output_enable_DL_DB.value = 1
    await Timer(1, unit="ns")
    assert dut.databus_DB.value == 0x77
    dut.output_enable_DL_DB.value = 0

    dut.output_enable_DL_ADL.value = 1
    await Timer(1, unit="ns")
    assert dut.databus_ADL.value == 0x77
    assert not dut.databus_DB.value.is_resolvable, "DB should be open again"


@cocotb.test()
async def test_program_counter(dut: "DUT"):
    """PCL and PCH load from ADL and ADH, increment as one 16-bit counter, and
    drive ADL/ADH and DB."""
    await reset(dut)
    await load_pc(dut, 0x12FE)
    assert await read_pc(dut) == (0x12FE, 0x12FE)

    await increment_pc(dut)
    assert await read_pc(dut) == (0x12FF, 0x12FF)

    # PCLC carries from PCL into PCH
    await increment_pc(dut)
    assert await read_pc(dut) == (0x1300, 0x1300)

    # The program counter wraps from 0xFFFF to 0x0000
    await load_pc(dut, 0xFFFF)
    await increment_pc(dut)
    assert await read_pc(dut) == (0x0000, 0x0000)


@cocotb.test()
async def test_program_counter_loads_only_on_phi1(dut: "DUT"):
    """ADL/PCL and ADH/PCH only load the select registers during phi1."""
    await reset(dut)
    await load_pc(dut, 0x1234)

    dut.databus_ADH.value = Force(0x66)
    dut.databus_ADL.value = Force(0x55)
    dut.load_ADH_PCH.value = 1
    dut.load_ADL_PCL.value = 1
    await phase(dut.phi2)
    dut.load_ADH_PCH.value = 0
    dut.load_ADL_PCL.value = 0
    dut.databus_ADH.value = Release()
    dut.databus_ADL.value = Release()
    await Timer(1, unit="ns")

    assert await read_pc(dut) == (0x1234, 0x1234), "PC should not load from ADH/ADL during phi2"
