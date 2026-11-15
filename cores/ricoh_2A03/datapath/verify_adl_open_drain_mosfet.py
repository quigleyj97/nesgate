from typing import TYPE_CHECKING

import cocotb
from cocotb.triggers import Timer

if TYPE_CHECKING:
    from adl_open_drain_mosfet import AdlOpenDrainMosfet as DUT

# The ADL open drain MOSFETs can only pull bits 0-2 of the ADL bus low, one
# control signal per bit. Bits 3-7 have no MOSFET and must never be driven.
SIGNAL_FOR_BIT = {
    0: "signal_0_ADL0",
    1: "signal_0_ADL1",
    2: "signal_0_ADL2",
}


async def check(dut: "DUT", active: set[str], reason: str):
    """Assert the given control signals, then check every bit of the ADL bus.

    A bit should be pulled low ('0') only while its control signal is active,
    and should otherwise float ('Z'). 'Z' is checked literally, so 'X' or 'U'
    (e.g. an undriven or contended net) also counts as a failure.
    """
    for signal in SIGNAL_FOR_BIT.values():
        getattr(dut, signal).value = 1 if signal in active else 0
    await Timer(1, unit="fs")

    # GHDL's VPI doesn't expose individual elements of a vector port, so read
    # the whole bus and index into its string form, which is MSB first.
    bus = str(dut.adl_bus.value)
    mismatches = []
    for bit in range(8):
        signal = SIGNAL_FOR_BIT.get(bit)
        if signal is None:
            expected, why = "Z", "no open drain MOSFET on this bit"
        elif signal in active:
            expected, why = "0", f"pulled low by {signal}"
        else:
            expected, why = "Z", f"{signal} is inactive"
        actual = bus[7 - bit]
        if actual != expected:
            mismatches.append(f"  bit {bit}: expected {expected} ({why}), got {actual}")

    assert not mismatches, (
        f"{reason}\n  active signals: {sorted(active) or 'none'}\n"
        f"  adl_bus (bit 7..0): {bus}\n" + "\n".join(mismatches)
    )


@cocotb.test()
async def test_adl_open_drain_mosfet(dut: "DUT"):
    """Test the ADL open drain MOSFET functionality"""
    await check(dut, set(),
                "With no signals active, the MOSFETs must not drive the bus")

    # Each signal must pull down only its own bit, so a miswired signal or a
    # bit that's driven when it shouldn't be shows up here.
    await check(dut, {"signal_0_ADL0"}, "signal_0_ADL0 must pull down only bit 0")
    await check(dut, {"signal_0_ADL1"}, "signal_0_ADL1 must pull down only bit 1")
    await check(dut, {"signal_0_ADL2"}, "signal_0_ADL2 must pull down only bit 2")

    # The decoder can assert several of these at once (e.g. to form a fixed
    # vector address), so the pull-downs must combine without interfering.
    await check(dut, {"signal_0_ADL0", "signal_0_ADL1"},
                "signal_0_ADL0 and signal_0_ADL1 together must pull down bits 0 and 1")
    await check(dut, {"signal_0_ADL0", "signal_0_ADL1", "signal_0_ADL2"},
                "All three signals together must pull down bits 0-2")

    # The bus must float again once released, rather than latching a value.
    await check(dut, set(), "After releasing all signals, the bus must float again")
