# The 6502 Instruction Decoder {#MOS6502_Instruction_Decoder}

This sub-core holds the instruction decoder: the predecode stage, the
instruction register, timing generation, the decoder ROM, the ready and
interrupt control logic, and the random logic that turns the decoder lines into
the @ref MOS_6502_Signals "control signals". @ref mos_6502 wires them
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
| @ref timing_generator | `timing_generator_formal.sv` | metaclock, with real Phi1/Phi2 phases of 3 to 7 metaclock cycles |
| @ref ready_controller | `ready_controller_formal.sv` | metaclock, with real Phi1/Phi2 phases of 3 to 7 metaclock cycles |
| @ref interrupt_controller | `interrupt_controller_formal.sv` | metaclock, with real Phi1/Phi2 phases of 3 to 7 metaclock cycles |
| @ref random_logic_controller | `random_logic_controller_formal.sv` | metaclock, with Phi1 and Phi2 changing freely |
| All eight, wired together | `decoder_formal.sv` | metaclock, with real Phi1/Phi2 phases of 3 to 7 metaclock cycles |

In the other unit proofs, Phi1 and Phi2 can change on any metaclock edge, and
can even be high at once, so they cover timings a real clock generator never
produces. Every latch powers up as documented in its entity.

The timing generator, ready controller and interrupt controller proofs keep no
model of their entity's latches, so there's no second copy of the VHDL to keep
in step with it. Each property relates the entity's own outputs at the end of
a phase to that phase's inputs and to its outputs at the end of the phases
before, as its documentation describes them ("T3 follows T2 one cycle later
while ready"), and every latched output must hold while its phase is low.
That needs real clocks, so these three use `two_phase_clock.sv`: Phi1 and Phi2
alternate and never overlap (as the @ref phased_clock_generator proof shows
they do), each phase lasts 3 to 7 metaclock cycles, and the outputs are read
on each phase's last metaclock edge, once the latch chains have settled.
Inputs change only as a phase starts. Mutating the VHDL (a T1X that ignores
`ready`, a write cycle that can stall, a level-triggered NMI, an IRQ that
ignores I, a reset that never ends, and 9 more) makes each proof fail on the
property you'd expect.

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

Cycle by cycle, with every output read at the end of Phi1 and holding
through Phi2:

- `T1` is `TRES1`, and `TRES2` is `TRESX`, both from Phi1.
- `T1X` follows `T0` one cycle later, while ready.
- `T0` is set outside `T1` when the next instruction takes 2 cycles
  (`TWOCYCLE`) or the current one is finishing (`TRES2`), and stays set until
  `T1X`.
- T2-T5 move `T1` on one stage per cycle while ready, hold while not ready,
  and clear on `TRES2`.
- `T6` follows a cycle with `SHIFT` and `MemOP` set while ready, and holds
  while not ready. `T7` follows a cycle of `T6` while ready.

Cover checks reach T5, T7, `T0` together with T2, a stall holding T3,
`TRES2` clearing the counter, and `T0` held until `T1X`.

### ready_controller

Phase by phase:

- `WR` is the write latch (`STOR`, `PC/DB`, lines 98 and 100, `T6` or `T7`,
  from Phi2) while ready, except during a reset.
- The R/W pin holds `WR`, inverted, from Phi1 for the whole cycle.
- `ready` is `RDY`, or `WR` from the last Phi1, so a write cycle never
  stalls, and holds through Phi1.
- `ReadyPhi1` is `ready` from Phi1, held through Phi2. `PRDY` is `RDY` from
  Phi2, then Phi1.

On every step, a cycle that isn't ready never writes, and a reset never
writes (so the BRK sequence's pushes become reads).

### interrupt_controller

Phase by phase. Two of the states the documentation describes aren't
outputs, so the harness follows them as it defines them: BRK cycle 6 (from
`0/ADL0`, which marks BRK T5 while ready), and a pending NMI (`DONMI`), from
an edge on the `/NMI` pin until `BRK6E`, or, for an edge during the vector
cycles, from the first Phi1 after them.

- `RESP` is `/RES` from Phi2. `RESP` sets `DORES`, which holds until `BRK6E`.
- BRK T5 while ready starts cycle 6, which holds while not ready. `BRK6E` is
  cycle 6 while ready, from Phi2 of cycle 6 through Phi1 of cycle 7.
- In the vector cycles (T5 while ready, then cycle 6), `0/ADL0` is on during
  T5 and `0/ADL1` during a reset. `0/ADL2` is only on outside a reset, and
  only starts for a pending NMI. `0/ADL1` and `0/ADL2` are never on at once.
- A reset clears `B_OUT`. Otherwise it only goes low at T0 or branch T2
  (line 80), for a pending NMI or for `/IRQ` (from the Phi2 before) while I is
  clear, and such an IRQ always clears it. It then stays low until `BRK6E`,
  which sets it again.
- `BRK6E` only happens while ready.

What the controller does over whole instruction sequences (an NMI taken after
the vector cycles, bounded latency) is checked in the decoder proof below.

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
each phase lasts anywhere from 3 metaclock cycles (the fewest @ref metaclock
allows) to 7 (the top level's `METACLOCKS_PER_PHASE`), chosen freely for every
phase. `/RES` is held low for the first 3
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
- `interrupts` (RDY and `/RES` high after the power-on reset, `/NMI` and
  `/IRQ` free, with `/NMI` held low until its vector is fetched, as the PPU
  holds it until it's acknowledged, and no JAM opcode): every documented
  opcode still takes its documented cycles and writes, including the one an
  interrupt arrives in, and the injected BRK takes BRK's. An NMI has its vector
  fetched within 15 cycles of its edge, and an IRQ held low with I clear
  within 14 cycles. Both bounds are tight (one cycle less fails). The IRQ's
  worst case arrives during a taken branch, which doesn't check for
  interrupts in its last cycle, so it waits through the next instruction (up
  to 8 cycles) and then the BRK sequence. The NMI's arrives too late to take
  over the vector of a sequence already running, so the CPU first runs one
  instruction of that handler, as the 6502 does.

In every task, after the power-on reset, the interrupt controller keeps its
contract with the rest of the CPU. It's stated from the pins, as they stood
at the end of each Phi2, and the vector lines and `B_OUT` as each cycle
starts, once their latches have settled:

- Only a pending NMI edge, or `/IRQ` low while I is clear, starts an
  interrupt sequence (`B_OUT` going low outside a reset). So I masks IRQ, and
  nothing else starts one.
- The next opcode fetched after that is BRK, whatever was on the data bus.
- `B_OUT` stays low from then until the vector is fetched, so P is pushed
  with B clear.
- The NMI vector (`0xFFFA`) is only fetched for a pending NMI, and never
  during a reset. The reset vector (`0xFFFC`) is only fetched after `/RES`
  was low.

Cover checks reach a page-crossing `LDA abs,X` (5 cycles), a taken branch
crossing a page (4 cycles), a branch not taken (2 cycles), `INC abs,X` writing twice, a JAM opcode running
past 8 cycles, a stall at T3, a write while RDY is low, an NMI, an IRQ and an
NMI each fetching their vector, and an opcode fetched while I masks an IRQ.

### Not verified

- The unofficial opcodes' cycle counts, apart from finishing within 8 cycles.
- Whether a page is really crossed. The ALU carry is free, so the decoder
  proof only checks that a taken branch or an indexed read takes one of its
  two documented counts, not which one a given address needs.
- Stall timing, and interrupts during stalls or resets: the `interrupts` task
  keeps RDY and `/RES` high, and the `free` task only checks safety
  properties.
- The exact interrupt latency. The `interrupts` task proves an upper bound,
  not the documented cycle an interrupt is taken on (such as a taken branch
  delaying it by an instruction).
- An `/NMI` pulse that goes high again before its vector is fetched. The
  `interrupts` task holds `/NMI` low until then.
- That I is set by the BRK sequence, or that an interrupt pushes the right PC.
  The flags are free inputs here, and the pushes go through the datapath.
- What each control command does for each instruction. The decoder proof
  checks dispatch, timing and writes; the CPU testbench checks the commands'
  effect on the datapath.
- That the latch chains settle on a real chip. The decoder proof assumes RDY,
  the flags, DB and the ALU carry hold still for the last metaclock cycles of
  the phases that sample them, which the real sources do. An input that
  changed on a phase's last edge would split a decision between two latches
  of the same phase (see @ref metaclock).
- In the timing generator, ready controller and interrupt controller proofs,
  inputs that change partway through a phase, or overlapping clocks. Each
  input there changes only as a phase starts. The decoder proof wires the
  units together, where their inputs come from each other's latches.
- Inputs other than 0 and 1 (`'X'`, `'U'`, `'Z'`). The proofs run on the
  synthesized netlist, where those don't exist.
- The properties are checked against the decoder table, the documentation
  and the 6502's documented timing, not against the real chip's transistor
  netlist.

## Predecode

During @ref MOS_6502_Phi2 the opcode on the external data bus is latched into
the @ref predecode_register. The @ref predecode_logic then classifies it right
away (it's combinational) as @ref MOS_6502_Signal_TWOCYCLE and/or
@ref MOS_6502_Signal_IMPLIED. It also passes the opcode on to the instruction
register, replacing it with BRK while @ref MOS_6502_Signal_0_IR is asserted.

The real chip stores the opcode inverted and produces active-low `/TWOCYCLE`
and `/IMPLIED` outputs. This core keeps everything active-high, like the rest
of its control signals.

## Instruction register

During @ref MOS_6502_Phi1, while @ref MOS_6502_Signal_FETCH is asserted,
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

- The short cycle counter makes @ref MOS_6502_Signal_T0, the last cycle of an
  instruction, and @ref MOS_6502_Signal_T1X, the cycle after it.
  @ref MOS_6502_Signal_T1, the opcode fetch cycle, comes from
  @ref MOS_6502_Signal_TRES1 latched during @ref MOS_6502_Phi1.
- The extended cycle counter shifts `T1` through @ref MOS_6502_Signal_T2 to
  @ref MOS_6502_Signal_T5, one cycle at a time.
  @ref MOS_6502_Signal_TRESX clears it.
- The very long cycle counter makes the read-modify-write cycles
  @ref MOS_6502_Signal_T6 and @ref MOS_6502_Signal_T7.

While @ref MOS_6502_Signal_ready is low, the counters hold their current
cycle, and `T7` doesn't start. `T1` just follows `TRES1`, so the dispatch logic
stalls it.

`TRES1` and `TRESX` come from the @ref random_logic_controller.
`ready` comes from the @ref ready_controller. The real chip outputs most of the
timing signals active-low. This core keeps them all active-high.

## Decoder ROM

The @ref decoder_rom is a 21-to-130 demultiplexer, sometimes called the PLA. It
decodes the opcode from the @ref instruction_register, and the cycle from the
@ref timing_generator (@ref MOS_6502_Signal_T0, @ref MOS_6502_Signal_T1X
and @ref MOS_6502_Signal_T2 to @ref MOS_6502_Signal_T5), into the 130
@ref MOS_6502_Decoder_Lines "decoder lines". It is purely combinational.

Each line is a NOR gate on some of the 21 input lines: `/T0`, `/T1X`,
`/T2`-`/T5`, both polarities of `IR2`-`IR7`, `/IR0`, `/IR1`, and `IR01` (`IR0`
or `IR1`). So each line matches the opcodes in one cycle (or in any cycle). The
masks come straight from the "raw bits" in the decoder table. The testbench
checks them against the table's decoded masks, for every opcode and cycle.

The extra logic that sits in the decoder area is part of this entity too. Line
129 (push/pull) is removed from lines 83, 90 and 128. Line 73 (Branch T0) is
gated by @ref MOS_6502_Signal_PRDY. Line 128 (IMPL) also checks `IR0`.

The real chip takes the cycle signals and outputs the lines active-low. This
core keeps them all active-high.

## Ready control

The @ref ready_controller stalls the CPU while the external
@ref MOS_6502_Signal_RDY pin is low, by dropping
@ref MOS_6502_Signal_ready, which holds the @ref timing_generator on its
current cycle. The 6502 can only stall on read cycles, so it also works out
which cycles write (@ref MOS_6502_Signal_WR). A cycle that wrote during the
last Phi1 stays ready whatever `RDY` does, and a stalled cycle never writes.

It also makes two delayed copies of the ready state:
@ref MOS_6502_Signal_ReadyPhi1 for the ACR latch and branch logic, and
@ref MOS_6502_Signal_PRDY for the @ref decoder_rom. On the real chip the
`/ready` and `WR` latches are part of the dispatcher, and the `/PRDY` latches
sit next to the `RDY` pad.

@ref MOS_6502_Signal_STOR and @ref MOS_6502_Signal_PC_DB come from the
@ref random_logic_controller, and lines 98 and 100 from the @ref decoder_rom.
@ref MOS_6502_Signal_DORES comes from the @ref interrupt_controller. The R/W
pin's latch is part of the ready controller too: it holds `WR`, inverted, from
Phi1 through the whole cycle.

## Interrupt control

The @ref interrupt_controller handles the @ref MOS_6502_Signal_NMI,
@ref MOS_6502_Signal_IRQ and @ref MOS_6502_Signal_RES pins. The 6502
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

During @ref MOS_6502_Signal_T0 (or T2 of a branch), a pending NMI, or an IRQ
while the I flag (@ref MOS_6502_Signal_I_OUT) is clear, clears
@ref MOS_6502_Signal_B_OUT. That makes the next fetch inject BRK, and pushes
P with B clear. A reset (@ref MOS_6502_Signal_DORES) clears it too, and turns
the pushes into reads. The decoder only counts up to T5, so the interrupt logic
makes the last cycle itself, and ends the sequence with
@ref MOS_6502_Signal_BRK6E.

NMI is edge-triggered: a falling edge of `/NMI` is remembered (`DONMI`) until
the next BRK sequence ends, and holding it low doesn't trigger another one. An
NMI that arrives during a BRK or IRQ sequence, before T5, takes over its vector
fetch, since the vector is only chosen at T5. One that arrives during the vector
fetch waits for the next instruction.

During T5 and T6 the controller pulls the low bits of ADL low
(@ref MOS_6502_Signal_0_ADL0, @ref MOS_6502_Signal_0_ADL1,
@ref MOS_6502_Signal_0_ADL2), so the precharged bus reads the vector:
`0xFFFA` for NMI, `0xFFFC` for reset, and `0xFFFE` for IRQ and BRK.

On the real chip this logic sits in the dispatcher area, and the `/NMI`, `/IRQ`
and `/RES` latches sit next to their pads. This core keeps every internal signal
active-high, but the pins themselves are active-low. The @ref random_logic_controller injects BRK, and uses `BRK6E` and
@ref MOS_6502_Signal_RESP to reset the cycle counters. The
@ref status_register sets I on `BRK6E`, and pushes `B_OUT` as bit 4 of P.

## Random logic and dispatch

The @ref random_logic_controller is the rest of the control unit. On the real
chip it is scattered between the decoder and the datapath, which is why it's
called random logic. This core models it as one entity, because its circuits
share so many intermediate signals.

The dispatcher sequences each instruction:

- Instruction completion makes @ref MOS_6502_Signal_TRES1 and
  @ref MOS_6502_Signal_TRESX for the @ref timing_generator. Short
  instructions end at `T0`, or at T2 of a branch that isn't taken. Long ones
  end after their memory cycle, or after `T7` for read-modify-write. Indexed
  addressing takes an extra cycle when it crosses a page, which the ACR latch
  remembers.
- The PC increments (@ref MOS_6502_Signal_I_PC) after each opcode or operand
  fetch, except for single-byte opcodes (@ref MOS_6502_Signal_IMPLIED) and
  hardware interrupts (@ref MOS_6502_Signal_B_OUT).
- @ref MOS_6502_Signal_FETCH loads the @ref instruction_register after `T1`.
  @ref MOS_6502_Signal_0_IR injects BRK outside the fetch, or during it if an
  interrupt is pending. So the predecode logic only sees the real opcode
  during the fetch, and an operand byte can't trigger
  @ref MOS_6502_Signal_TWOCYCLE.
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
@ref MOS_6502_Signal_S_S either: the real register needs it to refresh its
dynamic input latch from its output latch, but the FPGA's flip-flops hold their
value on their own.
