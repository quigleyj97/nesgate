"""Tests for the length decoder (`length_decoder`), against the documented
length table."""

from typing import TYPE_CHECKING

import cocotb
from cocotb.triggers import Timer

if TYPE_CHECKING:
    from length_decoder import LengthDecoder as DUT

#: The length, in half frames, for each index (bits 7-3 of $4003 and co.)
LENGTHS = [
    10, 254, 20, 2, 40, 4, 80, 6, 160, 8, 60, 10, 14, 12, 26, 14,
    12, 16, 24, 18, 48, 20, 96, 22, 192, 24, 72, 26, 16, 28, 32, 30,
]


@cocotb.test()
async def test_length_table(dut: "DUT"):
    """Each index decodes to one less than its length, whatever bits 2-0
    hold."""
    for index, length in enumerate(LENGTHS):
        for low_bits in (0b000, 0b101, 0b111):
            dut.bus_DB_in.value = (index << 3) | low_bits
            await Timer(1, unit="ns")
            value = int(dut.length_value.value)
            assert value == length - 1, f"Index {index} decoded to {value}, expected {length - 1}"
