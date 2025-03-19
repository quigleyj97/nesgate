import cocotb
from cocotb.triggers import Timer, FallingEdge
from cocotb.handle import SimHandleBase
from cocotb.clock import Clock

@cocotb.test()
async def run_core(dut: SimHandleBase):
    clock = Clock(dut.clock, 2, units="fs")
    await cocotb.start(clock.start())

    dut._log.info("Running test")

    await Timer(100, units="fs")
    await FallingEdge(dut.clock)

    dut._log.info("Finishing test")

    assert True