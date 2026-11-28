"""Tests for the sprite DMA buffer and pin direction control (`dma_buffer`)."""

from typing import TYPE_CHECKING

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, Timer

if TYPE_CHECKING:
    from dma_buffer import DmaBuffer as DUT


async def setup(dut: "DUT"):
    dut.phi2.value = 0
    dut.write_ppu_SPR_PPU.value = 0
    dut.read_not_write_R_NOT_W.value = 1
    dut.read_R4015.value = 0
    dut.debug_read_DBGRD.value = 0
    dut.bus_DB_in.value = 0
    cocotb.start_soon(Clock(dut.metaclock, 2, unit="ns").start())
    await FallingEdge(dut.metaclock)


async def phi2_with(dut: "DUT", value: int):
    dut.bus_DB_in.value = value
    dut.phi2.value = 1
    await Timer(8, unit="ns")
    dut.phi2.value = 0
    await Timer(8, unit="ns")


@cocotb.test()
async def test_buffer(dut: "DUT"):
    """The buffer keeps the last byte on the bus during Phi2, and drives it
    back during SPR/PPU only."""
    await setup(dut)
    await phi2_with(dut, 0x5A)
    assert dut.bus_DB_out.value == 0xFF, "Drove the bus without SPR/PPU"
    dut.bus_DB_in.value = 0x00
    dut.write_ppu_SPR_PPU.value = 1
    await Timer(1, unit="ns")
    assert dut.bus_DB_out.value == 0x5A, "Didn't drive the buffered byte"
    dut.write_ppu_SPR_PPU.value = 0


@cocotb.test()
async def test_pin_direction(dut: "DUT"):
    """R/W is low while the CPU or the DMA writes. The pins drive the bus
    during reads, except reads of $4015 or debug reads."""
    await setup(dut)
    # (CPU R/W, SPR/PPU, R4015, DBGRD) -> (R/W pin, RD, WR)
    cases = {
        (1, 0, 0, 0): (1, 1, 0),
        (0, 0, 0, 0): (0, 0, 1),
        (1, 1, 0, 0): (0, 0, 1),
        (1, 0, 1, 0): (1, 1, 1),
        (1, 0, 0, 1): (1, 1, 1),
    }
    for (rw, spr_ppu, r4015, dbgrd), expected in cases.items():
        dut.read_not_write_R_NOT_W.value = rw
        dut.write_ppu_SPR_PPU.value = spr_ppu
        dut.read_R4015.value = r4015
        dut.debug_read_DBGRD.value = dbgrd
        await Timer(1, unit="ns")
        got = (int(dut.read_not_write_RW.value), int(dut.pins_input_RD.value),
               int(dut.pins_isolated_WR.value))
        assert got == expected, f"{(rw, spr_ppu, r4015, dbgrd)}: {got}, expected {expected}"
