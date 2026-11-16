# The 6502 Instruction Decoder {#Ricoh2A03_Instruction_Decoder}

This sub-core will hold the instruction decoder: the predecode stage, the
instruction register, timing generation, and the decoder ROM that drives the
@ref Ricoh_2A03_Signals "control signals". So far only the predecode stage is
implemented, plus the instruction register.

## Components

- @ref predecode_register
- @ref predecode_logic
- @ref instruction_register

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
