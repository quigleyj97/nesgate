# The 6502 Instruction Decoder {#Ricoh2A03_Instruction_Decoder}

This sub-core holds the instruction decoder: the predecode stage, the
instruction register, timing generation, the decoder ROM, the ready and
interrupt control logic, and the random logic that turns the decoder lines into
the @ref Ricoh_2A03_Signals "control signals". @ref mos_6502 wires them
together with the ALU and the datapath.

## Components

- @ref predecode_register
- @ref predecode_logic
- @ref instruction_register
- @ref timing_generator
- @ref decoder_rom
- @ref ready_controller
- @ref interrupt_controller
- @ref random_logic_controller

## Predecode

During @ref Ricoh_2A03_Phi2 the opcode on the external data bus is latched into
the @ref predecode_register. The @ref predecode_logic then classifies it right
away (it's combinational) as @ref Ricoh_2A03_Signal_TWOCYCLE and/or
@ref Ricoh_2A03_Signal_IMPLIED. It also passes the opcode on to the instruction
register, replacing it with BRK while @ref Ricoh_2A03_Signal_0_IR is asserted.

The real chip stores the opcode inverted and produces active-low `/TWOCYCLE`
and `/IMPLIED` outputs. This core keeps everything active-high, like the rest
of its control signals.

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

`TRES1` and `TRESX` come from the @ref random_logic_controller.
`ready` comes from the @ref ready_controller. The real chip outputs most of the
timing signals active-low. This core keeps them all active-high.

## Decoder ROM

The @ref decoder_rom is a 21-to-130 demultiplexer, sometimes called the PLA. It
decodes the opcode from the @ref instruction_register, and the cycle from the
@ref timing_generator (@ref Ricoh_2A03_Signal_T0, @ref Ricoh_2A03_Signal_T1X
and @ref Ricoh_2A03_Signal_T2 to @ref Ricoh_2A03_Signal_T5), into the 130
@ref Ricoh_2A03_Decoder_Lines "decoder lines". It is purely combinational.

Each line is a NOR gate on some of the 21 input lines: `/T0`, `/T1X`,
`/T2`-`/T5`, both polarities of `IR2`-`IR7`, `/IR0`, `/IR1`, and `IR01` (`IR0`
or `IR1`). So each line matches the opcodes in one cycle (or in any cycle). The
masks come straight from the "raw bits" in the decoder table. The testbench
checks them against the table's decoded masks, for every opcode and cycle.

The extra logic that sits in the decoder area is part of this entity too. Line
129 (push/pull) is removed from lines 83, 90 and 128. Line 73 (Branch T0) is
gated by @ref Ricoh_2A03_Signal_PRDY. Line 128 (IMPL) also checks `IR0`.

The real chip takes the cycle signals and outputs the lines active-low. This
core keeps them all active-high.

## Ready control

The @ref ready_controller stalls the CPU while the external
@ref Ricoh_2A03_Signal_RDY pin is low, by dropping
@ref Ricoh_2A03_Signal_ready, which holds the @ref timing_generator on its
current cycle. The 6502 can only stall on read cycles, so it also works out
which cycles write (@ref Ricoh_2A03_Signal_WR). A cycle that wrote during the
last Phi1 stays ready whatever `RDY` does, and a stalled cycle never writes.

It also makes two delayed copies of the ready state:
@ref Ricoh_2A03_Signal_ReadyPhi1 for the ACR latch and branch logic, and
@ref Ricoh_2A03_Signal_PRDY for the @ref decoder_rom. On the real chip the
`/ready` and `WR` latches are part of the dispatcher, and the `/PRDY` latches
sit next to the `RDY` pad.

@ref Ricoh_2A03_Signal_STOR and @ref Ricoh_2A03_Signal_PC_DB come from the
@ref random_logic_controller, and lines 98 and 100 from the @ref decoder_rom.
@ref Ricoh_2A03_Signal_DORES comes from the @ref interrupt_controller. The R/W
pin's latch is part of the ready controller too: it holds `WR`, inverted, from
Phi1 through the whole cycle.

## Interrupt control

The @ref interrupt_controller handles the @ref Ricoh_2A03_Signal_NMI,
@ref Ricoh_2A03_Signal_IRQ and @ref Ricoh_2A03_Signal_RES pins. The 6502
handles all of them with the BRK sequence, the same 7 cycles as the BRK
instruction:

| Cycle | BRK sequence |
|-------|--------------|
| T0 | Check for interrupts, fetch the opcode (or force BRK) |
| T1 | Fetch and discard the next byte |
| T2 | Push PCH |
| T3 | Push PCL |
| T4 | Push P |
| T5 | Read the vector low byte |
| T6 | Read the vector high byte (`BRK6E`) |

During @ref Ricoh_2A03_Signal_T0 (or T2 of a branch), a pending NMI, or an IRQ
while the I flag (@ref Ricoh_2A03_Signal_I_OUT) is clear, clears
@ref Ricoh_2A03_Signal_B_OUT. That makes the next fetch inject BRK, and pushes
P with B clear. A reset (@ref Ricoh_2A03_Signal_DORES) clears it too, and turns
the pushes into reads. The decoder only counts up to T5, so the interrupt logic
makes the last cycle itself, and ends the sequence with
@ref Ricoh_2A03_Signal_BRK6E.

NMI is edge-triggered: a falling edge of `/NMI` is remembered (`DONMI`) until
the next BRK sequence ends, and holding it low doesn't trigger another one. An
NMI that arrives during a BRK or IRQ sequence, before T5, takes over its vector
fetch, since the vector is only chosen at T5. One that arrives during the vector
fetch waits for the next instruction.

During T5 and T6 the controller pulls the low bits of ADL low
(@ref Ricoh_2A03_Signal_0_ADL0, @ref Ricoh_2A03_Signal_0_ADL1,
@ref Ricoh_2A03_Signal_0_ADL2), so the precharged bus reads the vector:
`0xFFFA` for NMI, `0xFFFC` for reset, and `0xFFFE` for IRQ and BRK.

On the real chip this logic sits in the dispatcher area, and the `/NMI`, `/IRQ`
and `/RES` latches sit next to their pads. This core keeps every internal signal
active-high, but the pins themselves are active-low. The @ref random_logic_controller injects BRK, and uses `BRK6E` and
@ref Ricoh_2A03_Signal_RESP to reset the cycle counters. The
@ref status_register sets I on `BRK6E`, and pushes `B_OUT` as bit 4 of P.

## Random logic and dispatch

The @ref random_logic_controller is the rest of the control unit. On the real
chip it is scattered between the decoder and the datapath, which is why it's
called random logic. This core models it as one entity, because its circuits
share so many intermediate signals.

The dispatcher sequences each instruction:

- Instruction completion makes @ref Ricoh_2A03_Signal_TRES1 and
  @ref Ricoh_2A03_Signal_TRESX for the @ref timing_generator. Short
  instructions end at `T0`, or at T2 of a branch that isn't taken. Long ones
  end after their memory cycle, or after `T7` for read-modify-write. Indexed
  addressing takes an extra cycle when it crosses a page, which the ACR latch
  remembers.
- The PC increments (@ref Ricoh_2A03_Signal_I_PC) after each opcode or operand
  fetch, except for single-byte opcodes (@ref Ricoh_2A03_Signal_IMPLIED) and
  hardware interrupts (@ref Ricoh_2A03_Signal_B_OUT).
- @ref Ricoh_2A03_Signal_FETCH loads the @ref instruction_register after `T1`.
  @ref Ricoh_2A03_Signal_0_IR injects BRK outside the fetch, or during it if an
  interrupt is pending. So the predecode logic only sees the real opcode
  during the fetch, and an operand byte can't trigger
  @ref Ricoh_2A03_Signal_TWOCYCLE.
- The branch logic works out whether a branch is taken, and which way it goes,
  so that a taken branch that crosses a page gets a cycle to fix up PCH.

The rest makes the control commands: register, ALU, PC, bus and flags control.
Most commands are latched during Phi2 from the current cycle's decoder lines,
and drive the datapath during the next Phi1. The ones the real chip cuts off
during Phi2 are cut off here too.

The real chip uses many active-low signals and inverted latches. This core
keeps them all active-high. It also differs from the Verilog model in one
place: `ADH/ABH`, where it follows the wiki's transistor-level schematics
instead. See the entity's documentation for details.

`DSA` has nowhere to go yet, since the decimal adjust adders aren't
implemented. The @ref stack_pointer doesn't take
@ref Ricoh_2A03_Signal_S_S either: the real register needs it to refresh its
dynamic input latch from its output latch, but the FPGA's flip-flops hold their
value on their own.
