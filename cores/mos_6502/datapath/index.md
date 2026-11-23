# MOS 6502 Datapath {#MOS_6502_Datapath}

This sub-core holds data-path related code, including the main CPU registers,
the input data latch, and the bus multiplexer, which models the precharge, open
drain and pass MOSFETs on each bus.

## Components

- @ref index_register
- @ref accumulator
- @ref data_input_latch
- @ref program_counter_low
- @ref program_counter_high
- @ref stack_pointer
- @ref bus_multiplexer

## Wiring

@ref mos_6502_datapath wires the subunits together on the SB, DB, ADH and ADL
buses. The real buses are precharged high during phi2, can only be pulled low,
and can be joined into one node by the pass MOSFETs. When several drivers are
enabled on one bus, it reads their wired-AND, which some unofficial opcodes
(e.g. SBX) rely on. `'Z'` drivers on a shared signal can't model that: in
simulation a `'0'` and a `'1'` resolve to `'X'`, and in synthesis yosys merges
tri-state drivers into a mux, not an AND. So the design has no tri-states:

- Every subunit drives its own signal for each bus it drives (e.g. `AC_DB`),
  with its value while enabled and all ones (released) otherwise.
- The datapath ANDs every driver of a bus into one `drivers_*` signal,
  including the drivers from outside the datapath.
- @ref bus_multiplexer applies the open drain MOSFETs, and `SB/DB` and `SB/ADH`
  merge the buses they connect, giving the `bus_*` values that every subunit
  reads.

Subunits outside the datapath (e.g. the ALU) drive the buses through the
`drive_*` ports, all ones when not driving, and read them from the `databus_*`
ports.

The data pins are split into `data_in` (read by the data input latch) and
`data_out` (driven by the data output register), since the FPGA fabric has no
internal tri-states. `data_out` reads all ones unless the CPU is writing during
Phi2, when the real pins would be released.

It holds the accumulator, the X and Y index registers, the stack pointer, the
status register, the address bus registers, the data input/output latches, the
program counter (see @ref MOS_6502_PC_Registers), and the bus multiplexer.
@ref mos_6502 wires it to the ALU (@ref logic_core). The decimal adjust adders
aren't implemented yet.

## Formal verification

Each subunit of the datapath has its own SymbiYosys proof in `proofs/`, and
@ref mos_6502_datapath has one more that checks them wired together. `./formal`
runs them all. Every proof has two tasks: `prove`, which shows that the
properties hold, and `cover`, which shows that every interesting case can
actually happen, so no property passes trivially.

The clocked proofs are unbounded (`abc pdr`), so they hold after any number of
steps, not only the first few. A port that can drive a bus reads all ones
while it's disabled, the same as an undriven, precharged bus.

| Subunit | Harness | Clocking |
|---|---|---|
| @ref index_register | `index_register_formal.sv` | metaclock only |
| @ref accumulator | `accumulator_formal.sv` | metaclock only |
| @ref data_input_latch | `data_input_latch_formal.sv` | metaclock only |
| @ref data_output_latch | `data_output_latch_formal.sv` | metaclock only |
| @ref stack_pointer | `stack_pointer_formal.sv` | metaclock only |
| @ref status_register | `status_register_formal.sv` | real Phi1/Phi2 phases of 3-7 metaclock cycles (`two_phase_clock.sv`) |
| @ref program_counter_low | `program_counter_low_formal.sv` | real Phi1/Phi2 phases of 3-7 metaclock cycles (`two_phase_clock.sv`) |
| @ref program_counter_high | `program_counter_high_formal.sv` | real Phi1/Phi2 phases of 3-7 metaclock cycles (`two_phase_clock.sv`) |
| @ref bus_multiplexer | `bus_multiplexer_formal.sv` | combinational, one instant |
| @ref mos_6502_datapath | `datapath_formal.sv` | real Phi1/Phi2 phases of 3-7 metaclock cycles (`two_phase_clock.sv`) |

Every register powers up as 0.

### index_register, accumulator, data_input_latch

On every metaclock edge, the register takes its input (`data_in`, SB, or the
data pins) if its load signal (`load`, `SB/AC`, or Phi2) was high, and holds
its value otherwise. Each output port drives the held value while its enable
is high, independently of the others, and reads all ones otherwise.

### data_output_latch

On every metaclock edge, the register takes DB if Phi1 was high, and holds
otherwise. The data pins drive the held value only during Phi2 of a write
(`R/W` low), and read all ones (released) otherwise.

### stack_pointer

On every metaclock edge, the input latch takes SB if `SB/S` was high, and the
output latch takes the input latch's old value if Phi2 was high. `S/SB` and
`S/ADL` drive the output latch. So a value loaded from SB reaches the outputs
only in a later Phi2, and S keeps driving its old value while it loads a new
one (as JSR needs).

### status_register

The proof runs phase by phase, with real Phi1/Phi2 clocks, and reads each flag
at the end of a phase. It keeps no model of the register: the flags are
outputs, so each one is checked against its own value at the end of the phase
before. During Phi1, each flag loads from its selected sources:

- C: DB bit 0 (`DB0/C`), IR5 (`IR5/C`) or ACR (`ACR/C`)
- Z: DB bit 1 (`DB1/Z`) or whether DB is 0 (`DBZ/Z`)
- I: DB bit 2 (`DB2/I`) or IR5 (`IR5/I`), or else 1 during `BRK6E`
- D: DB bit 3 (`DB3/D`) or IR5 (`IR5/D`)
- V: DB bit 6 (`DB6/V`), AVR (`AVR/V`), 1 (`1/V`) or 0 (`0/V`)
- N: DB bit 7 (`DB7/N`)

When more than one source is selected, the flag loads their AND, as the real
chip's latch node does: a 0 from any of them wins. A flag holds when none of
its sources is selected, and every flag holds through Phi2. `I_OUT` is I or
`BRK6E`, and every other `*_OUT` is its flag. `I_OUT` hides the I latch during
`BRK6E`, so the harness follows the latch by the rule above. `P/DB` pushes N,
V, 1, `B_OUT`, D, I, Z, C (bit 7 to bit 0).

### program_counter_low and program_counter_high

The proofs run phase by phase, with real Phi1/Phi2 clocks. The select
registers and the program counter registers aren't outputs (PCL and PCH only
show through their bus ports), so the harness follows them a phase at a time:

- During Phi1, PCLS takes PCL (`PCL/PCL`) or ADL (`ADL/PCL`), and holds while
  neither is selected. PCHS works the same way with PCH (`PCH/PCH`) and ADH
  (`ADH/PCH`). Both hold through Phi2.
- During Phi2, PCL takes PCLS + `1/PC`, and PCH takes PCHS + PCLC. Both hold
  through Phi1. Both wrap from 0xFF to 0x00, so the program counter wraps from
  0xFFFF to 0x0000.
- PCLC is set exactly when `1/PC` is high and PCLS is 0xFF.
- `PCL/DB`, `PCL/ADL`, `PCH/DB` and `PCH/ADH` drive the register's value.

The random logic selects a select register's source only outside Phi2, and
never both sources at once (they're complements), so the proofs assume the
same. The PCH property is a plain 8-bit increment, so the proof also shows
that the design's two nibble incrementers carry into each other correctly.

### bus_multiplexer

For every combination of drivers and controls, a bit of a bus reads 0 exactly
when something on its node pulls it low: the bus's own drivers (from inside or
outside the datapath), its open drain MOSFETs (`0/ADL0`-`0/ADL2`, `0/ADH0`,
`0/ADH(1-7)`), or a bus that `SB/DB` or `SB/ADH` joins it to. So a joined bus
always reads the same as SB, and ADL never sees any other bus. Cover checks
reach, among others, the NMI vector's low byte (0xFA) formed by the open drain
MOSFETs alone, ADH pulling DB low through SB, and an internal and an external
driver wired-AND together.

### mos_6502_datapath

This proof checks the whole datapath, phase by phase, with real Phi1/Phi2
clocks. At the end of each phase, it checks every output (the four buses, the
address pins and the flags) against that phase's inputs and the outputs at
the end of the phase before, following the registers that aren't outputs as
their documentation defines them, the same as the proofs above:

- Every register reads the bus it's wired to, and drives the buses it's wired
  to.
- The address bus registers, PCLS, PCHS, the data output register and the
  flags only load during Phi1. DL, S and PCL/PCH only load during Phi2.
- PCL's carry out increments PCH.
- Each bus reads the wired-AND of every driver on it, inside the datapath or
  outside it, and SB/DB and SB/ADH join SB with DB and ADH.
- The address pins and the flags hold through Phi2, and the data pins drive
  the data output register through Phi2 of a write.

Every input changes only as a phase starts. The proof assumes what the random
logic guarantees: A, X, Y and the stack pointer don't load from SB during
Phi2, PCLS and PCHS never select both sources, and P isn't pushed onto DB
while DBZ/Z loads Z from it. A cover check reaches A and X on SB together, as
SBX does.

PDR can't prove Z directly: under DBZ/Z, Z loads from the NOR of all of DB,
which it can't learn one bit at a time. So `datapath.sby` splits the proof
into three tasks. `lemma` proves that DB settles within a phase's first two
edges, from the third edge of Phi1 on (`lemma_db_settled`, one bit at a
time). `z` assumes that to prove `check_z` and `check_flags_phi2`, and `rest`
proves every other property. Together they prove every assertion.

### Not verified

- Inputs other than 0 and 1 (`'X'`, `'U'`, `'Z'`). The proofs run on the
  synthesized netlist, where those don't exist. In simulation, the bus
  multiplexer passes an `'X'`, `'U'` or stray `'Z'` driver through as `'X'`,
  which a cocotb testbench checks.
- What a real chip does when two clock edges arrive on the same formal step,
  or how many metaclock cycles each phase needs (see @ref metaclock).
- The properties are checked against definitions of each register taken from
  its documentation, not against the real chip's transistor netlist.
