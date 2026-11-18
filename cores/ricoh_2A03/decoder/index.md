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

## Formal verification

Each subunit of the decoder has its own SymbiYosys proof in `proofs/`, and
`decoder_formal.sv` has one more that wires all eight together, as
@ref mos_6502 does. `./formal` runs them all. Every proof has a `prove` task,
which shows that the properties hold, and a `cover` task, which shows that
every interesting case can actually happen, so no property passes trivially.

The clocked proofs are unbounded (`abc pdr`), so they hold after any number of
steps, not only the first few. Where a property can be stated without
restating the VHDL, it is: the decoder ROM is checked against the decoded
opcode patterns of the decoder table, `TWOCYCLE` against a list of opcodes,
and the whole decoder against the documented cycle count of every opcode.

| Subunit | Harness | Clocking |
|---|---|---|
| @ref predecode_register | `predecode_register_formal.sv` | metaclock, with Phi2 changing freely |
| @ref predecode_logic | `predecode_logic_formal.sv` | combinational, one instant |
| @ref instruction_register | `instruction_register_formal.sv` | metaclock, with Phi1 changing freely |
| @ref decoder_rom | `decoder_rom_formal.sv` | combinational, one instant |
| @ref timing_generator | `timing_generator_formal.sv` | metaclock, with Phi1 and Phi2 changing freely |
| @ref ready_controller | `ready_controller_formal.sv` | metaclock, with Phi1 and Phi2 changing freely |
| @ref interrupt_controller | `interrupt_controller_formal.sv` | metaclock, with Phi1 and Phi2 changing freely |
| @ref random_logic_controller | `random_logic_controller_formal.sv` | metaclock, with Phi1 and Phi2 changing freely |
| All eight, wired together | `decoder_formal.sv` | metaclock, with real Phi1/Phi2 phases of 3 or 4 metaclock cycles |

In the unit proofs, Phi1 and Phi2 can change on any metaclock edge, and can
even be high at once, so they cover timings a real clock generator never
produces. Every latch powers up as documented in its entity.

### predecode_register and instruction_register

On every metaclock edge, the predecode register takes the data bus if Phi2 is
high, and the instruction register takes the predecoded opcode if Phi1 and
`FETCH` are both high. Otherwise each holds its value. Both power up as 0.

### predecode_logic

For every opcode, with and without `0/IR`:

- The opcode passes through, or becomes BRK (`0x00`) while `0/IR` is set.
- `TWOCYCLE` is set exactly for the 52 opcodes that finish in 2 cycles
  (immediate operands, and the single-byte opcodes other than PHP, PLP, PHA
  and PLA), listed by hand rather than by bit pattern.
- `IMPLIED` is set exactly for the opcodes in columns 8 and A of the opcode
  matrix.

### decoder_rom

Every one of the 130 lines is checked for every opcode, every combination of
the six cycle inputs (several at once included) and both values of `PRDY`,
against the opcodes it matches and the cycle it fires in, as decoded in the
decoder table. On top of that, line 73 (Branch T0) needs `PRDY`, and lines 83,
90 and 128 don't fire for the push/pull instructions.

### timing_generator

The model describes each counter by its outputs: during Phi2 the counters
sample their own outputs, and during Phi1 they move on to the next cycle.
`T1` and `TRES2` are `TRES1` and `TRESX` from Phi1. T2-T5 shift on from T1-T4
while ready, hold while not ready, and clear on `TRES2`. `T0` and `T1X`,
`T6` and `T7` follow their documented rules. Cover checks reach T5, T7, `T0`
together with T2, a stall holding T3, and `TRES2` clearing the counter.

### ready_controller

A model of the documented behavior, phase by phase, plus two properties the
rest of the CPU relies on, on every step: a cycle that isn't ready never
writes, and a reset never writes (so the BRK sequence's pushes become reads).

### interrupt_controller

A model of the pad latches, the BRK cycle 6-7 counter, the reset flip-flop,
the NMI edge detector, the B flag and the vector latches, plus: the vector
lines only ever select `0xFFFA`, `0xFFFC` or `0xFFFE`, a reset clears
`B_OUT`, and `BRK6E` only happens while ready.

### random_logic_controller

The controller is too large to restate as a model, and only the VHDL defines
its equations, so its unit proof checks what holds for any decoder lines:

- The register, accumulator, ALU input and PC select commands are off during
  Phi2.
- The commands that share a latch (`SB/ADD` and `0/ADD`, `ADL/PCL` and
  `PCL/PCL`, `ADH/PCH` and `PCH/PCH`, `SB/S` and `S/S`) have exactly one side
  on outside Phi2. The B input gets `DB/ADD` unless it gets `NOT DB` or `ADL`,
  and the ALU sums unless another operation is selected.
- Every command latched during Phi2 only changes on an edge during Phi2 (or
  when Phi2 cuts it off), and every command latched during Phi1 only on an
  edge during Phi1.
- `SHIFT`, `MemOP` and `STOR` come from their decoder lines, `FETCH` only
  happens while ready, `0/IR` injects BRK unless fetching with `B_OUT` set,
  and reset and `BRK6E` restart the cycle counters.

What each command does for each instruction is left to the decoder proof
below, and to the CPU testbench.

### The decoder

The harness makes real clocks: Phi1 and Phi2 alternate, never overlap, and
each phase lasts 3 or 4 metaclock cycles. `/RES` is held low for the first 3
cycles, as at power-on. The data bus, and so every opcode and operand, is free
on every metaclock edge. So are the flags, the branch direction on DB, and the
ALU carry (page crossings), but each only changes when its source can: the
carry during Phi2, the flags during Phi1, and DB outside Phi1.

- `clean` (no stalls or interrupts after the power-on reset): every one of
  the 151 documented opcodes takes its documented number of cycles, counted
  from one `FETCH` to the next, with any operands, flags and page crossings.
  A branch takes 2 cycles when it isn't taken (the flag that IR7-IR6 select
  differs from IR5), and 3 or 4 when it is. Indexed reads take one more cycle
  on a page crossing. Each opcode also writes to memory on the documented number of
  cycles (1 for a store or push, 2 for a read-modify-write or JSR, 3 for
  BRK). Every opcode but the 12 JAM opcodes finishes within 8 cycles, and the
  instruction register holds the byte the CPU read.
- `free` (RDY, `/NMI`, `/IRQ` and `/RES` free too, with RDY only changing
  during Phi1, as the 6502 datasheet requires): a write cycle never stalls,
  at most one of T2-T5 is set, and NMI is edge-triggered: once its vector has
  been fetched, another NMI needs `/NMI` to have gone high first.

Cover checks reach a page-crossing `LDA abs,X` (5 cycles), a taken branch
crossing a page (4 cycles), a branch not taken (2 cycles), `INC abs,X` writing twice, a JAM opcode running
past 8 cycles, a stall at T3, a write while RDY is low, and an NMI.

### Not verified

- The unofficial opcodes' cycle counts, apart from finishing within 8 cycles.
- Whether a page is really crossed. The ALU carry is free, so the decoder
  proof only checks that a taken branch or an indexed read takes one of its
  two documented counts, not which one a given address needs.
- Interrupt and stall timing in the decoder proof: the `clean` task assumes
  neither happens, and the `free` task only checks safety properties.
- What each control command does for each instruction. The decoder proof
  checks dispatch, timing and writes; the CPU testbench checks the commands'
  effect on the datapath.
- That the latch chains settle on a real chip. The decoder proof assumes RDY,
  the flags, DB and the ALU carry hold still for the last metaclock cycles of
  the phases that sample them, which the real sources do. An input that
  changed on a phase's last edge would split a decision between two latches
  of the same phase (see @ref metaclock).
- Inputs other than 0 and 1 (`'X'`, `'U'`, `'Z'`). The proofs run on the
  synthesized netlist, where those don't exist.
- The properties are checked against the decoder table, the documentation
  and the 6502's documented timing, not against the real chip's transistor
  netlist.

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
