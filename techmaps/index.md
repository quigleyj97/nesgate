# Yosys Techmaps {#techmaps}

This folder holds [Yosys techmap](https://yosyshq.readthedocs.io/projects/yosys/en/latest/cmd/techmap.html)
files that `synth` applies to the netlist before mapping it onto the FPGA. They
are build tooling, not part of the design: the VHDL in `cores/` is still the
only description of the hardware, and simulation never uses these files.

## Why Verilog?

A techmap replaces one of Yosys's internal cell types (e.g. `$tribuf`) with
other logic, using Yosys conventions: a `(* techmap_celltype = "..." *)`
attribute, a `_`-prefixed module name, and the cell's own ports and parameters.
Yosys only reads techmaps as Verilog or RTLIL, and VHDL can't target an internal
cell at all. Yosys never sees the VHDL anyway, since `synth` first converts the
design to Verilog with `ghdl --synth --out=verilog`.

## precharge_tribuf.v

The CPU's internal buses are precharged high, and @ref bus_multiplexer reads an
undriven (`'Z'`) bit as 1 (see @ref MOS_6502_Datapath). The ECP5 fabric has no
internal tri-state buffers, and GHDL's synthesis drops the `'Z'` choice, so in
the netlist that 1 has to come from the tri-state buffers themselves.

`synth` runs these passes on the flattened design:

```
tribuf -merge;
techmap -map ../techmaps/precharge_tribuf.v;
```

`tribuf -merge` merges each bus's drivers into a single `$tribuf` cell, and
this techmap turns each of those into a mux, `Y = EN ? A : all ones`, which
reads all ones while nothing drives the bus, like the precharge.

Yosys's built-in `tribuf -logic` can't do this: it leaves an undriven bus
undefined instead of high, and drops the enable of a buffer that is the only
driver of its net.

A driver that isn't a tri-state buffer, or that only drives some of a bus's
bits, doesn't merge, and Yosys warns about "multiple conflicting drivers" and
produces a broken netlist. `synth` makes that warning an error.
