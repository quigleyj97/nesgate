from typing import TYPE_CHECKING

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, NextTimeStep

if TYPE_CHECKING:
    from phased_clock_generator import PhasedClockGenerator as DUT

@cocotb.test()
async def verify_clock_phases(dut: "DUT"):
    clk = Clock(dut.clk_in, 2, unit='fs')
    cocotb.start_soon(clk.start())
    await FallingEdge(dut.clk_in)
    await NextTimeStep()

    assert dut.clk_in.value == False
    assert dut.clk_phi1.value == True
    assert dut.clk_phi2.value == False

    await FallingEdge(dut.clk_phi1)
    await NextTimeStep()

    assert dut.clk_phi1.value == False
    assert dut.clk_phi2.value == True

    await FallingEdge(dut.clk_phi2)
    await NextTimeStep()

    assert dut.clk_phi1.value == True
    assert dut.clk_phi2.value == False