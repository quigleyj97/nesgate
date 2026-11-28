# Registers and I/O {#Ricoh2A03_Registers}

- @ref register_decoder turns the CPU's reads and writes of `$4000`-`$401F`
  into strobes. It picks the register space from the CPU's address, but the
  register from the address on the pins, so a DMA during a CPU read of a
  register can select a different one.
- @ref io_ports drives the `OUT0`-`OUT2` pins from `$4016`, and the `/IN0`
  and `/IN1` pins while `$4016` and `$4017` are read.
- @ref debug_registers holds `LOCK`, and puts the channel outputs on the bus
  for test mode reads of `$4018`-`$401A`.
