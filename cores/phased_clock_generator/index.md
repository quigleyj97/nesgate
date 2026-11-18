# Phased Clock Generator {#PhasedClockGen}

This core implements a 2-phase set of exclusive signals, necessary to drive the
various subcomponents of the MOS 6502.

In effect, this module takes in 1 clock signal and outputs 2 signals at half
its frequency, one the inverse of the other, so exactly one of the two is high
at any given time. Each phase lasts one whole period of the input clock. There
is no gap between the phases: one falls at the same moment the other rises.

@ref phased_clock_generator

## Formal verification

`proofs/phased_clock_generator_formal.sv` checks the generator with an
unbounded proof (`abc pdr`), and `./formal` runs it. The input clock is a free
input under SymbiYosys's `multiclock on`, so it can rise or fall on any step,
or hold for any number of steps. The proof shows that:

- At power-up, Phi1 is high and Phi2 low.
- Phi1 and Phi2 are never both high, and never both low.
- `clk_out` always equals Phi2.
- The phases swap on every rising edge of `clk_in`, and at no other time:
  never on a falling edge, and never while `clk_in` holds its level.

Cover checks confirm that the phases swap both ways, that a falling edge goes
by with no swap, and that `clk_in` can hold high after a rising edge.

The proof assumes `clk_in` starts low, so the first step is never treated as
an edge.

### Not verified

- The non-overlap a real 6502 needs between Phi1 and Phi2. This core has no
  dead time between the phases, and the proof checks that it has none.
- Glitches between the two outputs. Each output comes from the same register,
  one through an inverter, so on real hardware they switch a gate delay apart.
  The proof runs on the netlist, where they switch on the same step.
