import cocotb
from cocotb.triggers import Timer, FallingEdge
from cocotb.handle import SimHandleBase
from cocotb.clock import Clock

@cocotb.test()
async def run_core(dut: SimHandleBase):
    clock = Clock(dut.clock, 2, units="fs")
    phi2 = Clock(dut.phi2, 2, units="fs")
    await cocotb.start(clock.start())
    await cocotb.start(make_inverted_clk(dut.phi1))
    await cocotb.start(phi2.start())

    dut._log.info("Running test")

    await Timer(100, units="fs")
    await FallingEdge(dut.clock)

    dut._log.info("Finishing test")

    assert True

async def make_inverted_clk(pin):
    await Timer(1, units="fs")
    clk = Clock(pin, 2, units="fs")
    await clk.start()