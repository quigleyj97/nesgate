# Clocks {#Ricoh_2A03_clocks}

The 2A03 runs everything off the 6502's two-phase clock, Phi1 and Phi2 (see
@ref MOS_6502_clocks). Most of the APU runs at half that rate, on two more
clocks made by the @ref aclk_generator.

## ACLK1 and ACLK2

An APU cycle is two CPU cycles. ACLK1 is high during the Phi1 of the first,
and ACLK2 during the Phi1 of the second:

```
CPU cycle   |    n    |   n+1   |   n+2   |   n+3

Phi1        |‾‾‾‾|____|‾‾‾‾|____|‾‾‾‾|____|‾‾‾‾|____

Phi2        |____|‾‾‾‾|____|‾‾‾‾|____|‾‾‾‾|____|‾‾‾‾

ACLK1       |‾‾‾‾|______________|‾‾‾‾|______________

ACLK2       __________|‾‾‾‾|______________|‾‾‾‾|____
```

Both are low during Phi2, which is when the CPU writes the APU's registers,
so a register write never lands in the middle of a counter step.

Most of the APU's sequential logic is a pair of latches, one open during each
phase:

- During ACLK1, the counters' carry latches work out their next values (see
  @ref apu_counter), and the control logic latches the state it'll act on.
- During ACLK2, the counters step or reload, and the LFSRs shift.

So the APU's control logic acts on the state as of the last ACLK1, which is
why a channel can take an APU cycle or two to respond to a register write.

The triangle channel's frequency and output counters are the exception: they
run on Phi1 and Phi2 instead, so they step every CPU cycle.

During reset (@ref Ricoh_2A03_Signal_RES), ACLK1 and ACLK2 are both high in
every Phi1, so the counters cleared by reset see both phases. After reset,
ACLK1 comes first.

## Quarter and half frames

The @ref frame_counter divides ACLK further, into the quarter frame
(@ref Ricoh_2A03_Signal_LFO1, about 240 Hz) and the half frame
(@ref Ricoh_2A03_Signal_LFO2, about 120 Hz). Both are pulses during ACLK2.

## Metaclock

Every latch is sampled on the @ref metaclock while its enable is high, like
the 6502 core's. The longest chains of same-phase latches in the 2A03 are two
deep, so the 6502's rule holds: each phase must last at least three metaclock
cycles.
