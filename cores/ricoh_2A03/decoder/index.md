# The 6502 Instruction Decoder {#Ricoh2A03_Instruction_Decoder}

This sub-core will hold the instruction decoder: the predecode stage, the
instruction register, timing generation, and the decoder ROM that drives the
@ref Ricoh_2A03_Signals "control signals". So far the predecode stage, the
instruction register and the timing generation logic are implemented.

## Components

- @ref predecode_register
- @ref predecode_logic
- @ref instruction_register
- @ref timing_generator

## Predecode

During @ref Ricoh_2A03_Phi2 the opcode on the external data bus is latched into
the @ref predecode_register. The @ref predecode_logic then classifies it right
away (it's combinational) as @ref Ricoh_2A03_Signal_TWOCYCLE and/or
@ref Ricoh_2A03_Signal_IMPLIED. It also passes the opcode on to the instruction
register, replacing it with BRK while @ref Ricoh_2A03_Signal_0_IR is asserted.

The real chip stores the opcode inverted and produces active-low `/TWOCYCLE`
and `/IMPLIED` outputs. This core keeps everything active-high, like the rest
of its control signals.

Reference: [Breaknes: Predecode](https://github.com/emu-russia/breaks/blob/master/BreakingNESWiki_DeepL/6502/predecode.md)

## Instruction register

During @ref Ricoh_2A03_Phi1, while @ref Ricoh_2A03_Signal_FETCH is asserted,
the @ref instruction_register loads the opcode from the @ref predecode_logic. It
holds that opcode for the rest of the instruction, while the predecode stage is
already latching the next byte from the data bus.

The real chip stores the opcode inverted, outputs both polarities of each bit,
and merges `IR0` and `IR1` into one `IR01` line. This core outputs only the true
opcode, and leaves the inverted bits and `IR01` to the decoder.

## Timing generation

The @ref timing_generator tells the decoder ROM and the random logic which
cycle of an instruction the CPU is on. On the real chip this logic is spread
across the dispatcher, in between the rest of the random logic, but this core
models it as one unit, following the "Timing Generation Logic" block of Dr. 
Hanson's block diagram. It is three counters:

- The short cycle counter makes @ref Ricoh_2A03_Signal_T0, the last cycle of an
  instruction, and @ref Ricoh_2A03_Signal_T1X, the cycle after it.
  @ref Ricoh_2A03_Signal_T1, the opcode fetch cycle, comes from
  @ref Ricoh_2A03_Signal_TRES1 latched during @ref Ricoh_2A03_Phi1.
- The extended cycle counter shifts `T1` through @ref Ricoh_2A03_Signal_T2 to
  @ref Ricoh_2A03_Signal_T5, one cycle at a time.
  @ref Ricoh_2A03_Signal_TRESX clears it.
- The very long cycle counter makes the read-modify-write cycles
  @ref Ricoh_2A03_Signal_T6 and @ref Ricoh_2A03_Signal_T7.

While @ref Ricoh_2A03_Signal_ready is low, the counters hold their current
cycle, and `T7` doesn't start. `T1` just follows `TRES1`, so the dispatch logic
stalls it.

The signals that drive the counters (`TRES1`, `TRESX`, `/ready`) come from the
dispatch logic, which isn't implemented yet. The real chip outputs most of the
timing signals active-low. This core keeps them all active-high.
