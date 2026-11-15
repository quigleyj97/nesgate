from typing import TYPE_CHECKING

import cocotb
from cocotb.clock import Clock

if TYPE_CHECKING:
    from mos_6502 import Mos6502 as DUT
from cocotb.triggers import FallingEdge, Timer


@cocotb.test()
async def run_core(dut: "DUT"):
    clock = Clock(dut.clock, 2, unit="fs")
    phi2 = Clock(dut.phi2, 2, unit="fs")
    cocotb.start_soon(clock.start())
    cocotb.start_soon(make_inverted_clk(dut.phi1))
    cocotb.start_soon(phi2.start())

    dut._log.info("Running test")

    await Timer(100, unit="fs")
    await FallingEdge(dut.clock)

    dut._log.info("Finishing test")

    assert True

async def make_inverted_clk(pin):
    await Timer(1, unit="fs")
    clk = Clock(pin, 2, unit="fs")
    await clk.start()