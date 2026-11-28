# Audio Processing Unit {#Ricoh2A03_APU}

The APU is responsible for generating and mixing sound for the NES and Famicom,
and is hosted on-chip next to the 6502. The NTSC 2A03 includes 2 square wave
channels, a triange wave channel (which isn't volume-adjustable), a noise
channel, and a DPCM channel for primitive digital audio. An envelope controller
permits setting attack, decay, and sweep for the square and noise channels.

The actual die includes a DAC, resulting in the real 2A03 outputing analog audio
via 2 output pins, but these are not implemented here. The HDL instead outputs
audio digitally, for conversion external to this core.

## Testing

The tests include a test bench for the APU clocks, `apu_clock.py`, for easier
testing. This test bench drives the input clock and the FPGA metaclock, as well
as the buses and debug registers.
