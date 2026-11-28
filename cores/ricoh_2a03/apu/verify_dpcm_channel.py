"""Tests for the delta modulation channel (`dpcm_channel`), against the
documented behaviour.

The testbench plays memory: whenever the DMC owns the address pins, it answers
the fetch with the byte at the DMC's address. It plays the CPU too, which is
always reading unless a test says otherwise, so fetches can start.

A sample starts at $C000 + 64 × $4012, is 16 × $4013 + 1 bytes long, and is
played a bit at a time, LSB first, at the rate $4010 picks from the
documented NTSC table: each 1 raises the output by 2 and each 0 lowers it by 2,
unless that would take it out of 0-127.
"""

import itertools
from typing import TYPE_CHECKING

import cocotb

from cores.ricoh_2a03.apu_clock import ApuClock, Signals

if TYPE_CHECKING:
    from dpcm_channel import DpcmChannel as DUT

#: The rate for each index, in CPU cycles per bit
RATES = [428, 380, 340, 320, 286, 254, 226, 214, 190, 160, 142, 128, 106, 84, 72, 54]
FASTEST = 0x0F


class Bench:
    def __init__(self, dut: "DUT"):
        self.dut = dut
        self.clock = ApuClock(dut, watch=("DFLOAD",))
        self.memory = bytearray(0x10000)
        #: Every address fetched, in order
        self.fetches: list[int] = []
        #: DMCRDY at the end of each cycle run by `run_until_fetches`, which
        #: is when the CPU's ready latch has its last look at it
        self.ready: list[int] = []
        self.clock.serve = self.serve

    def serve(self) -> Signals:
        dut = self.dut
        if dut.dmc_address_bus_DMCAB.value == 1:
            address = int(dut.dmc_address.value)
            self.fetches.append(address)
            return {"bus_DB_in": self.memory[address]}
        return {}

    async def start(self):
        dut = self.dut
        dut.reset_RES.value = 1
        for name in ("debug_lock_LOCK", "write_W4010", "write_W4011", "write_W4012",
                     "write_W4013", "write_W4015", "read_R4015"):
            getattr(dut, name).value = 0
        dut.read_not_write_R_NOT_W.value = 1
        dut.bus_DB_in.value = 0
        await self.clock.start()
        await self.clock.cycles_(4)
        dut.reset_RES.value = 0
        await self.clock.cycles_(2)
        # The simulation carries on from the last test, which may have ended
        # mid-fetch, so forget anything seen during reset
        self.fetches.clear()
        self.ready.clear()

    async def play(self, address: int, length: int, control: int = FASTEST):
        """Set up a sample, and enable the channel."""
        await self.clock.write("write_W4010", control)
        await self.clock.write("write_W4012", address)
        await self.clock.write("write_W4013", length)
        await self.clock.write("write_W4015", 0x10)

    async def status(self) -> int:
        self.dut.read_R4015.value = 1
        await self.clock.cycle()
        value = int(self.dut.bus_DB_out.value)
        self.dut.read_R4015.value = 0
        return value

    async def run_until_fetches(self, count: int, limit: int = 20000):
        for _ in range(limit):
            if len(self.fetches) >= count:
                return
            await self.clock.cycle()
            self.ready.append(int(self.dut.dmc_ready_DMCRDY.value))
        raise AssertionError(f"Only {len(self.fetches)} fetches: {[hex(a) for a in self.fetches]}")


@cocotb.test()
async def test_rates(dut: "DUT"):
    """Each rate index plays a bit every documented number of CPU cycles."""
    bench = Bench(dut)
    await bench.start()
    pulses = bench.clock.pulses["DFLOAD"]
    for index, rate in enumerate(RATES):
        await bench.clock.write("write_W4010", index)
        pulses.clear()
        while len(pulses) < 4:
            await bench.clock.cycle()
        gaps = [b - a for a, b in itertools.pairwise(pulses[1:])]
        assert gaps == [rate, rate], f"Index {index}: bits every {gaps}, expected {rate}"


@cocotb.test()
async def test_fetches_sample(dut: "DUT"):
    """A sample is fetched from $C000 + 64 × $4012, 16 × $4013 + 1 bytes, in
    order. Then the channel disables itself."""
    bench = Bench(dut)
    await bench.start()
    await bench.play(address=0x10, length=0x01)
    await bench.run_until_fetches(17)
    assert bench.fetches == [0xC400 + i for i in range(17)], f"{[hex(a) for a in bench.fetches]}"
    # The fetch is noticed at the next ACLK1, and acted on at the ACLK2 after
    await bench.clock.cycles_(4)
    assert await bench.status() & 0x10 == 0, "Still enabled after the last byte"
    await bench.clock.cycles_(2000)
    assert len(bench.fetches) == 17, "Kept fetching"


@cocotb.test()
async def test_status_while_playing(dut: "DUT"):
    """$4015 bit 4 is set while bytes remain."""
    bench = Bench(dut)
    await bench.start()
    assert await bench.status() & 0x10 == 0, "Enabled before starting"
    await bench.play(address=0, length=0x02)
    await bench.run_until_fetches(5)
    assert await bench.status() & 0x10 == 0x10, "Not enabled while playing"


@cocotb.test()
async def test_loop(dut: "DUT"):
    """With loop set, the sample starts again after its last byte."""
    bench = Bench(dut)
    await bench.start()
    await bench.play(address=0x02, length=0x00, control=0x40 | FASTEST)
    await bench.run_until_fetches(4)
    assert bench.fetches == [0xC080] * 4, f"{[hex(a) for a in bench.fetches]}"
    assert await bench.status() & 0x10 == 0x10, "Disabled while looping"


@cocotb.test()
async def test_address_wraps(dut: "DUT"):
    """The address wraps from $FFFF to $8000."""
    bench = Bench(dut)
    await bench.start()
    await bench.play(address=0xFF, length=0x04)
    await bench.run_until_fetches(65, limit=65 * 8 * 54 + 1000)
    assert bench.fetches[63:] == [0xFFFF, 0x8000], f"{[hex(a) for a in bench.fetches[60:]]}"


@cocotb.test()
async def test_interrupt(dut: "DUT"):
    """With IRQ enabled, the end of a sample sets the interrupt, which $4015
    bit 7 reads, and writing $4015 or disabling the IRQ clears."""
    bench = Bench(dut)
    await bench.start()
    for clear_by in ("write_W4015", "write_W4010"):
        await bench.play(address=0, length=0x00, control=0x80 | FASTEST)
        await bench.run_until_fetches(len(bench.fetches) + 1)
        await bench.clock.cycles_(4)
        assert dut.dmc_interrupt_DMCINT.value == 1, "No interrupt at the end of the sample"
        assert await bench.status() & 0x80 == 0x80, "Bit 7 didn't read the interrupt"
        await bench.clock.write(clear_by, FASTEST if clear_by == "write_W4010" else 0)
        assert dut.dmc_interrupt_DMCINT.value == 0, f"{clear_by} didn't clear the interrupt"
        assert await bench.status() & 0x80 == 0, "Bit 7 still set"


@cocotb.test()
async def test_no_interrupt_when_disabled_or_looping(dut: "DUT"):
    """Without IRQ enabled, or with loop set, the end of a sample doesn't
    interrupt."""
    bench = Bench(dut)
    await bench.start()
    for control in (FASTEST, 0xC0 | FASTEST):
        await bench.play(address=0, length=0x00, control=control)
        await bench.run_until_fetches(len(bench.fetches) + 1)
        await bench.clock.cycles_(8)
        assert dut.dmc_interrupt_DMCINT.value == 0, f"Interrupted with $4010 = {control:#x}"
        await bench.clock.write("write_W4015", 0)
        await bench.clock.cycles_(1000)


@cocotb.test()
async def test_output_follows_bits(dut: "DUT"):
    """Each bit, LSB first, moves the output by +2 for a 1 and -2 for a 0,
    starting from the level written to $4011."""
    bench = Bench(dut)
    await bench.start()
    data = [0x0F, 0xA5, 0x00, 0xFF] + [0x55] * 13
    bench.memory[0xC000:0xC000 + len(data)] = bytes(data)
    await bench.clock.write("write_W4011", 64)
    assert int(dut.output_DMC.value) == 64, "Didn't load $4011"
    await bench.play(address=0, length=0x01)

    levels = []
    pulses = bench.clock.pulses["DFLOAD"]
    while len(levels) < 8 * 6:
        before = len(pulses)
        await bench.clock.cycle()
        if len(pulses) > before:
            levels.append(int(dut.output_DMC.value))
    deltas = [b - a for a, b in itertools.pairwise([64, *levels])]
    # The channel is silent until the first byte reaches the shift register
    while deltas[0] == 0:
        deltas.pop(0)
    expected = [2 if (byte >> bit) & 1 else -2 for byte in data for bit in range(8)]
    assert deltas[:32] == expected[:32], f"Deltas {deltas[:32]}"


@cocotb.test()
async def test_output_saturates(dut: "DUT"):
    """The output doesn't go above 127 or below 0."""
    bench = Bench(dut)
    await bench.start()
    for level, byte in ((126, 0xFF), (127, 0xFF), (1, 0x00), (0, 0x00)):
        bench.memory[0xC000:0xC011] = bytes([byte] * 17)
        await bench.clock.write("write_W4011", level)
        await bench.play(address=0, length=0x01)
        await bench.run_until_fetches(len(bench.fetches) + 4)
        assert int(dut.output_DMC.value) == level, (
            f"Level {level} with {byte:#04x} went to {int(dut.output_DMC.value)}"
        )
        await bench.clock.write("write_W4015", 0)
        await bench.clock.cycles_(1000)


@cocotb.test()
async def test_fetch_waits_for_read_cycle(dut: "DUT"):
    """A fetch only starts while the CPU is reading."""
    bench = Bench(dut)
    await bench.start()
    dut.read_not_write_R_NOT_W.value = 0
    await bench.play(address=0, length=0x01)
    await bench.clock.cycles_(50)
    assert bench.fetches == [], "Fetched while the CPU was writing"
    assert dut.dmc_ready_DMCRDY.value == 1, "Stalled the CPU while it was writing"
    dut.read_not_write_R_NOT_W.value = 1
    await bench.run_until_fetches(1, limit=10)


@cocotb.test()
async def test_stall_length(dut: "DUT"):
    """DMCRDY is low for 3 or 4 cycles per fetch, ending with the fetch
    cycle, depending on which half of an APU cycle the fetch is requested in."""
    bench = Bench(dut)
    await bench.start()
    await bench.play(address=0, length=0x02, control=FASTEST)
    await bench.run_until_fetches(12)
    # Let the last stall end
    await bench.run_until_fetches(13)
    # DMCRDY as the CPU samples it, at the end of Phi2: low runs
    lengths = []
    run = 0
    for ready in bench.ready:
        if ready == 0:
            run += 1
        elif run:
            lengths.append(run)
            run = 0
    assert len(lengths) == 12, f"{len(lengths)} stalls for the first 12 fetches: {lengths}"
    assert set(lengths) <= {3, 4}, f"Stall lengths {lengths}"
    assert len(set(lengths)) == 2, f"Stalls were all {lengths[0]} cycles"
