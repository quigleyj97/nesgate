"""Tests for the sprite DMA controller (`sprite_dma`), against the documented
behaviour.

After a write to $4014, the CPU is stalled for 513 or 514 cycles: one or two
cycles to line up with an APU cycle, then 256 pairs of a read from the page
and a write to $2004.
"""

from dataclasses import dataclass
from typing import TYPE_CHECKING

import cocotb

from cores.ricoh_2a03.apu_clock import ApuClock

if TYPE_CHECKING:
    from sprite_dma import SpriteDma as DUT


@dataclass(frozen=True)
class Cycle:
    ready: int
    read: int
    write: int
    address: int


async def setup(dut: "DUT") -> ApuClock:
    clock = ApuClock(dut)
    dut.reset_RES.value = 1
    dut.read_not_write_R_NOT_W.value = 1
    dut.write_W4014.value = 0
    dut.bus_DB_in.value = 0
    dut.dmc_running_RUNDMC.value = 0
    dut.dmc_ready_DMCRDY.value = 1
    await clock.start()
    await clock.cycles_(4)
    dut.reset_RES.value = 0
    await clock.cycles_(2)
    return clock


async def record(dut: "DUT", clock: ApuClock, count: int) -> list[Cycle]:
    cycles = []
    for _ in range(count):
        await clock.cycle()
        cycles.append(Cycle(
            ready=int(dut.ready_RDY.value),
            read=int(dut.read_memory_SPR_CPU.value),
            write=int(dut.write_ppu_SPR_PPU.value),
            address=int(dut.sprite_address.value),
        ))
    return cycles


async def write_4014(dut: "DUT", clock: ApuClock, page: int):
    """The CPU's write cycle: R/W low, and the strobe during Phi2. The CPU
    reads afterwards."""
    dut.read_not_write_R_NOT_W.value = 0
    await clock.write("write_W4014", page)
    dut.read_not_write_R_NOT_W.value = 1


def check_transfer(cycles: list[Cycle], page: int) -> int:
    """Check a whole DMA, and return how many cycles it stalled the CPU."""
    stalled = 0
    while cycles[stalled].ready == 0:
        stalled += 1
    lead = 0
    while not (cycles[lead].read or cycles[lead].write):
        lead += 1
    assert lead in (1, 2), f"The DMA started {lead} cycles after the write"
    for i in range(256):
        read, write = cycles[lead + 2 * i], cycles[lead + 2 * i + 1]
        assert (read.read, read.write) == (1, 0), f"Byte {i}: no read"
        assert read.address == (page << 8) | i, f"Byte {i}: read {read.address:#06x}"
        assert (write.read, write.write) == (0, 1), f"Byte {i}: no write"
    after = cycles[lead + 512]
    assert (after.read, after.write) == (0, 0), "Carried on after 256 bytes"
    return stalled


@cocotb.test()
async def test_transfer(dut: "DUT"):
    """A DMA reads each byte of the page in turn and writes it to $2004,
    stalling the CPU for 513 or 514 cycles."""
    clock = await setup(dut)
    stalls = []
    for page in (0x02, 0x07):
        await write_4014(dut, clock, page)
        assert dut.ready_RDY.value == 0, "RDY didn't drop on the write"
        cycles = await record(dut, clock, 520)
        stalls.append(check_transfer(cycles, page))
        # The next write lands in the other half of an APU cycle
        await clock.cycles_(3 if clock.next_is_aclk1 else 2)
    assert sorted(stalls) == [513, 514], f"Stalled for {stalls} cycles"


@cocotb.test()
async def test_waits_for_read_cycle(dut: "DUT"):
    """The DMA doesn't start while the CPU is writing, since the 6502 ignores
    RDY on writes."""
    clock = await setup(dut)
    await write_4014(dut, clock, 0x03)
    dut.read_not_write_R_NOT_W.value = 0
    cycles = await record(dut, clock, 6)
    assert not any(c.read or c.write for c in cycles), "Started during a write cycle"
    assert all(c.ready == 0 for c in cycles), "RDY rose before the DMA"
    dut.read_not_write_R_NOT_W.value = 1
    cycles = await record(dut, clock, 520)
    check_transfer(cycles, 0x03)


@cocotb.test()
async def test_pauses_for_dmc(dut: "DUT"):
    """While the DMC runs, the sprite DMA neither reads nor writes, and picks
    up where it left off."""
    clock = await setup(dut)
    await write_4014(dut, clock, 0x04)
    cycles = await record(dut, clock, 21)
    # Pause for an APU cycle, from an ACLK1, as RUNDMC does
    while not clock.next_is_aclk1:
        cycles += await record(dut, clock, 1)
    dut.dmc_running_RUNDMC.value = 1
    paused = await record(dut, clock, 2)
    dut.dmc_running_RUNDMC.value = 0
    assert not any(c.read or c.write for c in paused), "Kept going while the DMC ran"
    assert all(c.ready == 0 for c in paused), "RDY rose while the DMC ran"
    cycles += await record(dut, clock, 520)
    accesses = [c for c in cycles if c.read or c.write]
    reads = [c.address & 0xFF for c in accesses if c.read]
    assert reads == list(range(256)), "Skipped or repeated a byte"
    assert len(accesses) == 512, f"{len(accesses)} accesses"


@cocotb.test()
async def test_dmc_not_ready_stalls(dut: "DUT"):
    """RDY is also low while the DMC isn't ready."""
    clock = await setup(dut)
    dut.dmc_ready_DMCRDY.value = 0
    await clock.cycle()
    assert dut.ready_RDY.value == 0
    dut.dmc_ready_DMCRDY.value = 1
    await clock.cycle()
    assert dut.ready_RDY.value == 1
