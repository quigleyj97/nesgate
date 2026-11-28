"""Tests for the APU clock generator (`aclk_generator`).

The APU cycle is two CPU cycles. ACLK1 is high during the Phi1 of one, and
ACLK2 during the Phi1 of the other.
"""

from typing import TYPE_CHECKING

import cocotb
from cocotb.triggers import Timer

from cores.ricoh_2a03.apu_clock import METACLOCK_PERIOD, METACLOCKS_PER_PHASE, ApuClock

if TYPE_CHECKING:
    from aclk_generator import AclkGenerator as DUT


async def sample_cycle(dut: "DUT", clock: ApuClock) -> tuple[int, int, int, int]:
    """Run a CPU cycle, and return ACLK1 and ACLK2 in the middle of Phi1, then
    in the middle of Phi2."""
    half = METACLOCKS_PER_PHASE * METACLOCK_PERIOD // 2
    samples: list[int] = []

    async def probe():
        await Timer(half + 1, unit="ns")
        samples.extend([int(dut.aclk1.value), int(dut.aclk2.value)])
        await Timer(2 * half, unit="ns")
        samples.extend([int(dut.aclk1.value), int(dut.aclk2.value)])

    task = cocotb.start_soon(probe())
    await clock.cycle()
    await task
    return samples[0], samples[1], samples[2], samples[3]


@cocotb.test()
async def test_alternates_during_phi1(dut: "DUT"):
    """After reset, ACLK1 and ACLK2 take turns in Phi1, ACLK1 first, and are
    both low during Phi2."""
    clock = ApuClock(dut, drive_aclk=False)
    dut.reset_RES.value = 1
    await clock.start()
    await clock.cycles_(3)
    dut.reset_RES.value = 0

    expected_aclk1 = 1
    for i in range(12):
        aclk1, aclk2, aclk1_phi2, aclk2_phi2 = await sample_cycle(dut, clock)
        assert (aclk1, aclk2) == (expected_aclk1, 1 - expected_aclk1), (
            f"Cycle {i}: Phi1 had ACLK1={aclk1} ACLK2={aclk2}, expected ACLK{2 - expected_aclk1}"
        )
        assert (aclk1_phi2, aclk2_phi2) == (0, 0), f"Cycle {i}: ACLK high during Phi2"
        expected_aclk1 = 1 - expected_aclk1


@cocotb.test()
async def test_both_during_reset(dut: "DUT"):
    """During reset, ACLK1 and ACLK2 are both high in every Phi1, after the
    first cycle."""
    clock = ApuClock(dut, drive_aclk=False)
    dut.reset_RES.value = 1
    await clock.start()
    await clock.cycle()
    for i in range(4):
        aclk1, aclk2, _, _ = await sample_cycle(dut, clock)
        assert (aclk1, aclk2) == (1, 1), f"Reset cycle {i}: ACLK1={aclk1} ACLK2={aclk2}"
