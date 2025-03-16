import cocotb
from cocotb.handle import SimHandleBase
from cocotb.triggers import FallingEdge, NextTimeStep
from cocotb.clock import Clock

@cocotb.test()
async def verify_clock_phases(dut: SimHandleBase):
    clk = Clock(dut.clk_in, 2, units='fs')
    await cocotb.start(clk.start())
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