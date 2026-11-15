# MOS 6502 Datapath {#MOS_6502_Datapath}

This sub-core holds data-path related code, including the main CPU registers,
the input data latch, and the pass and precharge MOSFETs between each bus.

## Components

- @ref index_register
- @ref accumulator
- @ref data_input_latch
- @ref program_counter_low
- @ref program_counter_high

## Wiring

@ref mos_6502_datapath wires the subunits together on the SB, DB, ADH and ADL
buses. Several subunits drive each bus, releasing it to `'Z'` when they aren't
enabled. Since an unresolved `std_ulogic_vector` can only have one driver, the
buses are resolved `std_logic_vector`s, and each subunit's `std_ulogic_vector`
ports are converted at the port map, e.g.
`std_logic_vector(data_out) => databus_SB`.

So far it holds the accumulator, the X and Y index registers, the status
register, the address bus registers, the data input/output latches, and the
program counter (see @ref MOS_6502_PC_Registers). The stack pointer and MOSFETs
aren't wired in yet.
