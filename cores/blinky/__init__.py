from typing import TYPE_CHECKING

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, Timer

if TYPE_CHECKING:
    from blinky import Blinky as DUT

@cocotb.test()
async def verify_blinky(dut: "DUT"):
    clk = Clock(dut.clk, 2, unit='fs')
    cocotb.start_soon(clk.start())
    assert dut.led.value == 0

    await Timer(4 * 25, unit="fs")
    await FallingEdge(dut.clk)

    assert dut.led.value == 1

    await Timer(4 * 25, unit="fs")
    await FallingEdge(dut.clk)

    assert dut.led.value == 2