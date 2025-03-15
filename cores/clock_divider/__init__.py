import cocotb
from cocotb.clock import Clock
from cocotb.handle import SimHandleBase
from cocotb.triggers import RisingEdge, NextTimeStep

@cocotb.test()
async def verify_clock_division(dut: SimHandleBase):
    clk = Clock(dut.clk, 1, units='ns')
    await cocotb.start(clk.start())

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