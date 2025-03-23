# Ricoh 2A03 Core {#Ricoh2A03}

This core implements a Ricoh 2A03, a variant of the MOS 6502 microprocessor that
was used in the Nintendo Entertainment System and Famicom. Additional variants,
like the Ricoh 2A07, were used in some models of the system, such as the PAL NES.

Reference: @ref mos_6502

## Subpages

- @subpage Ricoh2A03_code_organization
- @subpage Ricoh_2A03_clocks
- @subpage Ricoh_2A03_Signals
- @subpage Ricoh_2A03_Datapath

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
