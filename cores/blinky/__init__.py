import cocotb
from cocotb.handle import SimHandleBase
from cocotb.triggers import Timer, FallingEdge
from cocotb.clock import Clock

@cocotb.test()
async def verify_blinky(dut: SimHandleBase):
    clk = Clock(dut.clk, 2, units='fs')
    await cocotb.start(clk.start())
    assert dut.led.value == 0

    await Timer(4 * 25, units="fs")
    await FallingEdge(dut.clk)

    assert dut.led.value == 1

    await Timer(4 * 25, units="fs")
    await FallingEdge(dut.clk)

    assert dut.led.value == 2