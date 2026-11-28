"""Tests for the 2A03's register decoder (`register_decoder`).

The register map is checked against the documented one: every write strobe
for its address, only during Phi2, and nothing for the addresses with no
register.
"""

from typing import TYPE_CHECKING

import cocotb
from cocotb.triggers import Timer

if TYPE_CHECKING:
    from register_decoder import RegisterDecoder as DUT

#: Write strobe for each address in $4000-$401F (debug ones need DBG)
WRITES = {
    0x00: "write_W4000", 0x01: "write_W4001", 0x02: "write_W4002", 0x03: "write_W4003",
    0x04: "write_W4004", 0x05: "write_W4005", 0x06: "write_W4006", 0x07: "write_W4007",
    0x08: "write_W4008", 0x0A: "write_W400A", 0x0B: "write_W400B", 0x0C: "write_W400C",
    0x0E: "write_W400E", 0x0F: "write_W400F", 0x10: "write_W4010", 0x11: "write_W4011",
    0x12: "write_W4012", 0x13: "write_W4013", 0x14: "write_W4014", 0x15: "write_W4015",
    0x16: "write_W4016", 0x17: "write_W4017",
}
DEBUG_WRITES = {0x1A: "write_W401A"}
READS = {0x15: "read_R4015", 0x16: "read_R4016", 0x17: "read_R4017"}
DEBUG_READS = {0x18: "read_R4018", 0x19: "read_R4019", 0x1A: "read_R401A"}
ALL_STROBES = [
    *WRITES.values(), *DEBUG_WRITES.values(), *READS.values(), *DEBUG_READS.values(),
    "debug_read_DBGRD",
]


async def decode(dut: "DUT", address: int, read: bool, phi1: int, debug: int = 0,
                 pin_address: int | None = None) -> set[str]:
    """Return the strobes that are high for this access."""
    dut.cpu_address.value = address
    dut.pin_address.value = (address if pin_address is None else pin_address) & 0x1F
    dut.read_not_write_R_NOT_W.value = int(read)
    dut.phi1.value = phi1
    dut.debug_DBG.value = debug
    await Timer(1, unit="ns")
    return {name for name in ALL_STROBES if getattr(dut, name).value == 1}


@cocotb.test()
async def test_writes(dut: "DUT"):
    """Each register's write strobe is high during Phi2 of a write to it, and
    no other strobe is."""
    for offset in range(0x20):
        strobes = await decode(dut, 0x4000 + offset, read=False, phi1=0)
        expected = {WRITES[offset]} if offset in WRITES else set()
        assert strobes == expected, f"Write ${0x4000 + offset:04X}: {strobes}, expected {expected}"


@cocotb.test()
async def test_no_writes_during_phi1(dut: "DUT"):
    """Writes are blocked during Phi1."""
    for offset in WRITES:
        strobes = await decode(dut, 0x4000 + offset, read=False, phi1=1)
        assert strobes == set(), f"Write ${0x4000 + offset:04X} during Phi1: {strobes}"


@cocotb.test()
async def test_reads(dut: "DUT"):
    """$4015-$4017 have read strobes, in either phase. Nothing else does
    without DBG."""
    for phi1 in (0, 1):
        for offset in range(0x20):
            strobes = await decode(dut, 0x4000 + offset, read=True, phi1=phi1)
            expected = {READS[offset]} if offset in READS else set()
            assert strobes == expected, f"Read ${0x4000 + offset:04X}: {strobes}, expected {expected}"


@cocotb.test()
async def test_outside_register_space(dut: "DUT"):
    """Addresses outside $4000-$401F decode nothing, even with matching low
    bits."""
    for address in (0x3015, 0x4020, 0x4035, 0x4115, 0x5015, 0xC015, 0x0015):
        for read in (True, False):
            strobes = await decode(dut, address, read=read, phi1=0, debug=1)
            assert strobes == set(), f"{'Read' if read else 'Write'} ${address:04X}: {strobes}"


@cocotb.test()
async def test_debug_registers(dut: "DUT"):
    """With DBG high, $4018-$401A read, $401A writes, and every read of
    $4000-$401F asserts DBGRD."""
    for offset in range(0x20):
        strobes = await decode(dut, 0x4000 + offset, read=True, phi1=0, debug=1)
        expected = {"debug_read_DBGRD"}
        if offset in READS:
            expected.add(READS[offset])
        if offset in DEBUG_READS:
            expected.add(DEBUG_READS[offset])
        assert strobes == expected, f"Debug read ${0x4000 + offset:04X}: {strobes}, expected {expected}"

    strobes = await decode(dut, 0x401A, read=False, phi1=0, debug=1)
    assert strobes == {"write_W401A"}, f"Debug write $401A: {strobes}"
    strobes = await decode(dut, 0x401A, read=False, phi1=0, debug=0)
    assert strobes == set(), f"Write $401A without DBG: {strobes}"


@cocotb.test()
async def test_register_from_pin_address(dut: "DUT"):
    """The CPU's address picks the register space, but the pins' address picks
    the register. So a CPU read of $4016 while a DMA puts $C015 on the pins
    reads $4015."""
    strobes = await decode(dut, 0x4016, read=True, phi1=0, pin_address=0xC015)
    assert strobes == {"read_R4015"}, f"Got {strobes}"
