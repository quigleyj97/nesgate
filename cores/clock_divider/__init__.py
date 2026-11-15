from typing import TYPE_CHECKING

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import NextTimeStep, RisingEdge

if TYPE_CHECKING:
    from clock_divider import ClockDivider as DUT

@cocotb.test()
async def verify_clock_division(dut: "DUT"):
    clk = Clock(dut.clk, 1, unit='ns')
    cocotb.start_soon(clk.start())

    await RisingEdge(dut.clk)

    assert dut.clk_out.value == 0

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    await NextTimeStep()

    assert dut.clk_out.value == 1

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    await NextTimeStep()

    assert dut.clk_out.value == 0