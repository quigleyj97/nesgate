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
and can be joined into one node by the pass MOSFETs, which `'Z'` drivers on a
shared signal can't model (a bidirectional pass MOSFET holds its own value, and
a strong precharge conflicts with every other driver). So each bus is split in
two:

- Every subunit that drives a bus drives its `drivers_*` signal, releasing it
  to `'Z'` when it isn't enabled. Since an unresolved `std_ulogic_vector` can
  only have one driver, these are resolved `std_logic_vector`s, and each
  subunit's `std_ulogic_vector` port is converted at the port map, e.g.
  `std_logic_vector(data_out) => drivers_SB`.
- @ref bus_multiplexer resolves the drivers into the `bus_*` values that every
  subunit reads: undriven bits read high, any bit pulled low reads low, and
  `SB/DB` and `SB/ADH` merge the buses they connect.

Subunits outside the datapath (e.g. the ALU) drive the buses through the
`drive_*` ports, and read them from the `databus_*` ports. A bus that nothing
outside drives gets all ones, which reads the same as `'Z'`.

The data pins are split into `data_in` (read by the data input latch) and
`data_out` (driven by the data output register, `'Z'` unless writing during
Phi2), since the FPGA fabric has no internal tri-states.
For synthesis, the @ref techmaps "precharge techmap" turns each bus's merged
tri-state drivers into a mux that reads all ones while nothing drives it.

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
steps, not only the first few. For every port that can drive a bus, the proof
applies the same `tribuf -merge` and precharge techmap that `synth` uses (see
@ref techmaps), so a disabled port reads all ones, the same as an undriven,
precharged bus.

| Subunit | Harness | Clocking |
|---|---|---|
| @ref index_register | `index_register_formal.sv` | metaclock only |
| @ref accumulator | `accumulator_formal.sv` | metaclock only |
| @ref data_input_latch | `data_input_latch_formal.sv` | metaclock only |
| @ref data_output_latch | `data_output_latch_formal.sv` | metaclock only |
| @ref stack_pointer | `stack_pointer_formal.sv` | metaclock only |
| @ref status_register | `status_register_formal.sv` | metaclock only |
| @ref program_counter_low | `program_counter_low_formal.sv` | `multiclock on`: the metaclock, with Phi2 changing freely |
| @ref program_counter_high | `program_counter_high_formal.sv` | `multiclock on`: the metaclock, with Phi2 changing freely |
| @ref bus_multiplexer | `bus_multiplexer_formal.sv` | combinational, one instant |
| @ref mos_6502_datapath | `datapath_formal.sv` | `multiclock on`: the metaclock, Phi1 and Phi2, each changing freely |

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

On every metaclock edge while Phi1 was high, each flag loads from its one
selected source:

- C: DB bit 0 (`DB0/C`), IR5 (`IR5/C`) or ACR (`ACR/C`)
- Z: DB bit 1 (`DB1/Z`) or whether DB is 0 (`DBZ/Z`)
- I: DB bit 2 (`DB2/I`) or IR5 (`IR5/I`), or else 1 during `BRK6E`
- D: DB bit 3 (`DB3/D`) or IR5 (`IR5/D`)
- V: DB bit 6 (`DB6/V`), AVR (`AVR/V`), 1 (`1/V`) or 0 (`0/V`)
- N: DB bit 7 (`DB7/N`)

A flag holds its value when none of its sources is selected, when more than one
is, or while Phi1 is low. `I_OUT` is I or `BRK6E`, and every other `*_OUT` is
its flag. `P/DB` pushes N, V, 1, `B_OUT`, D, I, Z, C (bit 7 to bit 0).

### program_counter_low and program_counter_high

- On every metaclock edge, the select register takes PCL (`PCL/PCL`), or else
  ADL (`ADL/PCL`), or else holds. PCHS works the same way with PCH
  (`PCH/PCH`) and ADH (`ADH/PCH`).
- On every metaclock edge while Phi2 was high, PCL takes PCLS + `1/PC`, and
  PCH takes PCHS + PCLC, each from just before the edge, and they hold while
  Phi2 is low. So, like the real latches, they keep the value from the last
  metaclock edge of Phi2. Both wrap from 0xFF to 0x00, so the
  program counter wraps from 0xFFFF to 0x0000.
- PCLC is set exactly when `1/PC` is high and PCLS is 0xFF.
- `PCL/DB`, `PCL/ADL`, `PCH/DB` and `PCH/ADH` drive the register's value.

The model of PCH is a plain 8-bit increment, so the proof also shows that the
design's two nibble incrementers carry into each other correctly.

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

This proof checks the whole datapath, against a model of every register built
from the same definitions as the proofs above, and the bus multiplexer's
wired-AND:

- Every register reads the bus it's wired to, and drives the buses it's wired
  to.
- The address bus registers, PCLS and PCHS only load while Phi1 is high.
- PCL's carry out increments PCH.
- Every output matches the model on every step: the four buses, the address
  pins, the data pins and the flags.

The metaclock, Phi1 and Phi2 are independent inputs here, so the proof covers
any timing of the three, including ones a real clock generator never produces.
Registers that aren't outputs are only checked through the buses they drive.

The proof assumes both clocks start low, and that **at most one subunit in the
datapath drives each bus at a time**. Synthesis merges a bus's drivers into a
single mux, and when several are enabled at once it reads the OR of their
values, not the wired-AND the real chip gives. (GHDL simulation gives `'X'`
instead.) Drivers from outside the datapath (`drive_*`) go through the bus
multiplexer, so they're wired-AND with the datapath's drivers correctly, and
aren't restricted.

### Not verified

- That the random logic never enables two datapath drivers on the same bus at
  once. The datapath proof assumes it, and the synthesized design gives the
  wrong value if it happens.
- That a disabled port is high impedance (`'Z'`) rather than driving 0xFF.
  With the precharge techmap, the two read the same. The cocotb testbenches
  check for `'Z'`.
- Inputs other than 0 and 1 (`'X'`, `'U'`, `'Z'`). The proofs run on the
  synthesized netlist, where those don't exist. In particular, the bus
  multiplexer proof can't distinguish an undriven bit from one driven high.
- What a real chip does when two clock edges arrive on the same formal step,
  or how many metaclock cycles each phase needs (see @ref metaclock).
- The properties are checked against definitions of each register taken from
  its documentation, not against the real chip's transistor netlist.
