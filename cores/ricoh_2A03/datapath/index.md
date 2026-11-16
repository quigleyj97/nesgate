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
`drive_*` ports, and read them from the `databus_*` ports.

It holds the accumulator, the X and Y index registers, the stack pointer, the
status register, the address bus registers, the data input/output latches, the
program counter (see @ref MOS_6502_PC_Registers), and the bus multiplexer. The
ALU (@ref logic_core) and the decimal adjust adders aren't wired in yet.
