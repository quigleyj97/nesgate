# MOS 6502 Core {#MOS6502}

This core implements the MOS 6502 microprocessor. The NES and Famicom use a
variant of it, the Ricoh 2A03 (and the 2A07 in the PAL NES), whose CPU is a
6502 with its decimal mode cut out of the masks. The `decimal_mode` generic of
@ref mos_6502 makes the same cut: leave it `true` for a stock 6502, and set it
to `false` for a 2A03. The 2A03's other parts, like its APU, aren't part of
this core.

Reference: @ref mos_6502

## Subpages

- @subpage MOS6502_code_organization
- @subpage MOS_6502_clocks
- @subpage MOS_6502_Signals
- @subpage MOS_6502_Datapath_Notes
- @subpage 6502_Registers

## A note on signal names

I use expanded signal names for readability and to keep what's left of my sanity
intact when working on this project. However, the 6502 is inherently a silicon
chip and while there have been a number of efforts to document silicon traces,
registers, and other circuitry, there's no 'real' standard that I can tell.

One commonly used reference is a block diagram prepared by Dr. Donald Hansen
and presented as part of a paper he presented in 1995 titled "A VHDL Conversion
Tool for Logic Equations with Embedded D Latches." [1] This diagram documents the
silicon at a low level and is said to be based on original engineering documents
created at MOS Technology in the 70s. [2]

As such, when naming a signal I will start with a name that makes sense to me,
but will also suffix it with the label in Dr. Hansen's block diagram to allow
for easier correlation between designs and HDL.

## References

[1]: https://www.witwright.com/DonPub/6502-Block-Diagram.pdf
[2]: https://www.nesdev.org/wiki/Visual6502wiki/650X_Schematic_Notes
