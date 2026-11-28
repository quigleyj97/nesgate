"""Tests for the address multiplexer (`address_multiplexer`)."""

from typing import TYPE_CHECKING

import cocotb
from cocotb.triggers import Timer

if TYPE_CHECKING:
    from address_multiplexer import AddressMultiplexer as DUT


async def select(dut: "DUT", spr_cpu: int, spr_ppu: int, dmc: int) -> int:
    dut.cpu_address.value = 0x8123
    dut.sprite_address.value = 0x0345
    dut.dmc_address.value = 0xC567
    dut.read_memory_SPR_CPU.value = spr_cpu
    dut.write_ppu_SPR_PPU.value = spr_ppu
    dut.dmc_address_bus_DMCAB.value = dmc
    await Timer(1, unit="ns")
    return int(dut.pin_address.value)


@cocotb.test()
async def test_sources(dut: "DUT"):
    """Each select puts its source on the pins, and with none the CPU's
    address goes through."""
    assert await select(dut, 0, 0, 0) == 0x8123, "CPU address"
    assert await select(dut, 1, 0, 0) == 0x0345, "Sprite DMA read"
    assert await select(dut, 0, 1, 0) == 0x2004, "Sprite DMA write"
    assert await select(dut, 0, 0, 1) == 0xC567, "DMC fetch"
