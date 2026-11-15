# The 6502 Instruction Decoder {#Ricoh2A03_Instruction_Decoder}

This sub-core will hold the instruction decoder: the predecode stage, the
instruction register, timing generation, and the decoder ROM that drives the
@ref Ricoh_2A03_Signals "control signals". So far only the predecode stage is
implemented.

## Components

- @ref predecode_register
- @ref predecode_logic

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
