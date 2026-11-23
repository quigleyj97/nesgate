from typing import TYPE_CHECKING

import cocotb
from cocotb.triggers import Timer
from cocotb.types import LogicArray

if TYPE_CHECKING:
    from bus_multiplexer import BusMultiplexer as DUT

#: All ones: nothing pulls any bit low
UNDRIVEN = 0xFF
DRIVERS = ["drive_SB", "drive_DB", "drive_ADH", "drive_ADL"]
CONTROLS = [
    "connect_SB_DB",
    "connect_SB_ADH",
    "clear_0_ADL0",
    "clear_0_ADL1",
    "clear_0_ADL2",
    "clear_0_ADH0",
    "clear_0_ADH_1_7",
]


async def reset(dut: "DUT"):
    for name in DRIVERS:
        getattr(dut, name).value = UNDRIVEN
    for name in CONTROLS:
        getattr(dut, name).value = 0
    await Timer(1, unit="ns")


def buses(dut: "DUT") -> tuple[int, int, int, int]:
    return (int(dut.bus_SB.value), int(dut.bus_DB.value), int(dut.bus_ADH.value), int(dut.bus_ADL.value))


@cocotb.test()
async def test_precharged_when_idle(dut: "DUT"):
    """With nothing driving them, every bus reads as precharged (all ones)."""
    await reset(dut)
    assert buses(dut) == (0xFF, 0xFF, 0xFF, 0xFF)


@cocotb.test()
async def test_undriven_bits_read_high(dut: "DUT"):
    """Bits nobody pulls low read high, even when other bits are driven."""
    await reset(dut)
    dut.drive_DB.value = LogicArray("11110101")
    await Timer(1, unit="ns")
    assert int(dut.bus_DB.value) == 0xF5


@cocotb.test()
async def test_buses_isolated(dut: "DUT"):
    """Without the pass MOSFETs, each bus only sees its own drivers."""
    await reset(dut)
    dut.drive_SB.value = 0x11
    dut.drive_DB.value = 0x22
    dut.drive_ADH.value = 0x33
    dut.drive_ADL.value = 0x44
    await Timer(1, unit="ns")
    assert buses(dut) == (0x11, 0x22, 0x33, 0x44)


@cocotb.test()
async def test_sb_db_both_directions(dut: "DUT"):
    """SB/DB passes a value from SB to DB, or from DB to SB."""
    await reset(dut)
    dut.connect_SB_DB.value = 1
    dut.drive_SB.value = 0x5A
    await Timer(1, unit="ns")
    assert int(dut.bus_DB.value) == 0x5A
    assert int(dut.bus_ADH.value) == 0xFF, "ADH should not be connected"

    dut.drive_SB.value = UNDRIVEN
    dut.drive_DB.value = 0xA5
    await Timer(1, unit="ns")
    assert int(dut.bus_SB.value) == 0xA5


@cocotb.test()
async def test_pass_releases(dut: "DUT"):
    """Once the driver releases a connected bus, both sides return to precharged.

    (A bidirectional 'Z' model of the pass MOSFET would latch the old value.)
    """
    await reset(dut)
    dut.connect_SB_DB.value = 1
    dut.drive_SB.value = 0x0F
    await Timer(1, unit="ns")
    dut.drive_SB.value = UNDRIVEN
    await Timer(1, unit="ns")
    assert (int(dut.bus_SB.value), int(dut.bus_DB.value)) == (0xFF, 0xFF)

    dut.drive_DB.value = 0xF0
    await Timer(1, unit="ns")
    assert (int(dut.bus_SB.value), int(dut.bus_DB.value)) == (0xF0, 0xF0)


@cocotb.test()
async def test_sb_adh_and_chain(dut: "DUT"):
    """SB/ADH joins ADH to SB, and with SB/DB too, DB reaches ADH through SB."""
    await reset(dut)
    dut.connect_SB_ADH.value = 1
    dut.drive_ADH.value = 0x3C
    await Timer(1, unit="ns")
    assert int(dut.bus_SB.value) == 0x3C
    assert int(dut.bus_DB.value) == 0xFF, "DB should not be connected"

    dut.drive_ADH.value = UNDRIVEN
    dut.connect_SB_DB.value = 1
    dut.drive_DB.value = 0x96
    await Timer(1, unit="ns")
    assert buses(dut)[:3] == (0x96, 0x96, 0x96)


@cocotb.test()
async def test_wired_and(dut: "DUT"):
    """When two joined buses are both driven, a low bit on either wins."""
    await reset(dut)
    dut.connect_SB_DB.value = 1
    dut.drive_SB.value = 0xF0
    dut.drive_DB.value = 0x3C
    await Timer(1, unit="ns")
    assert (int(dut.bus_SB.value), int(dut.bus_DB.value)) == (0x30, 0x30)


@cocotb.test()
async def test_interrupt_vectors(dut: "DUT"):
    """0/ADL0-2 pull bits of the precharged ADL bus low to form the vectors."""
    await reset(dut)
    # (0/ADL0, 0/ADL1, 0/ADL2) for the low byte of each vector
    for clears, expected in [
        ((1, 0, 1), 0xFA),  # NMI
        ((1, 1, 0), 0xFC),  # Reset
        ((1, 0, 0), 0xFE),  # IRQ/BRK
    ]:
        dut.clear_0_ADL0.value, dut.clear_0_ADL1.value, dut.clear_0_ADL2.value = clears
        await Timer(1, unit="ns")
        assert int(dut.bus_ADL.value) == expected, f"Expected ADL {expected:#04x}, got {dut.bus_ADL.value}"


@cocotb.test()
async def test_open_drain_adh(dut: "DUT"):
    """0/ADH0 and 0/ADH(1-7) pull ADH low, e.g. to 0x00 for the zero page."""
    await reset(dut)
    dut.clear_0_ADH0.value = 1
    await Timer(1, unit="ns")
    assert int(dut.bus_ADH.value) == 0xFE
    dut.clear_0_ADH0.value = 0
    dut.clear_0_ADH_1_7.value = 1
    await Timer(1, unit="ns")
    assert int(dut.bus_ADH.value) == 0x01, "Stack page (0x01)"
    dut.clear_0_ADH0.value = 1
    await Timer(1, unit="ns")
    assert int(dut.bus_ADH.value) == 0x00, "Zero page"

    # The pull-down is on ADH itself, so it reaches SB through SB/ADH
    dut.connect_SB_ADH.value = 1
    await Timer(1, unit="ns")
    assert int(dut.bus_SB.value) == 0x00


@cocotb.test()
async def test_conflict_stays_visible(dut: "DUT"):
    """An uninitialized driver, or a stray 'Z' left over from a tri-state
    driver, reads 'X', not a silent value."""
    await reset(dut)
    dut.drive_SB.value = LogicArray("XZ111110")
    await Timer(1, unit="ns")
    assert str(dut.bus_SB.value) == "XX111110"
