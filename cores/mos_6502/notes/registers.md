# 6502 Registers {#6502_Registers}

The 6502 has quite a few registers, and most of them aren't anything
particularly special (eg, the data output register just takes the DB bus and
latches it out to the data pins). A few are significant either because of their
importance to programming or because of their implementation, and those
registers are documented here.

## The X and Y Index Registers {#MOS_6502_XY_Registers}

These registers are used as program registers to stash variables, but can also
be used for indexed addressing. In this addressing mode, the instruction's data
address is computed with some combination of a literal word and the value of
these registers (either as a direct read, or an 'indirect' pointer-style read)
This removes a byte from index-addressed instructions, saving 1 CPU cycle.

## The Processor Status Register (P) {#MOS_6502_P_Register}

The P register stores flags regarding recently executed instructions, such as
whether a carry-out from the ALU occurred or whether the result of the last
operation was 0. Due to how much of the CPU is reused for address operations,
there are a set of control signals specific to this register to control when
these flags can be set. One signal, SV, is uniquely mapped to an external pin,
to set the V flag. There's no way to do that from software absent causing an
overflow, unlike most of the other flags which have explicit set/clear
operations like `SEC`/`CLC`.

## The Program Counter (PCL, PCH) {#MOS_6502_PC_Registers}

The 16-bit program counter is split into a low byte (@ref program_counter_low)
and a high byte (@ref program_counter_high). Each half has a select register
(PCLS, PCHS), increment logic, and an output register (PCL, PCH).

- During phi1, each select register loads either from its own output register
  (`PCL/PCL`, `PCH/PCH`), which keeps the current value, or from its address
  bus (`ADL/PCL`, `ADH/PCH`). The random control logic asserts `PCL/PCL`
  whenever it doesn't assert `ADL/PCL`, and `PCH/PCH` whenever it doesn't
  assert `ADH/PCH`.
- During phi2, the output registers latch the select register's value plus the
  increment. PCL increments on `I/PC`, and PCH increments on the carry out of
  PCL (@ref MOS_6502_PCLC), with @ref MOS_6502_PCHC carrying between its
  nibbles.
- The output registers can drive DB (`PCL/DB`, `PCH/DB`) and the address buses
  (`PCL/ADL`, `PCH/ADH`) in either phase.

@ref mos_6502_datapath gates the select register loads with phi1, since during
phi2 the ADL and ADH buses are precharged.
