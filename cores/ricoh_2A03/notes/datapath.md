# 6502 Datapath {#Ricoh_2A03_Datapath}

The 6502 uses a series of internal databuses to connect each part of the CPU
together, in some cases linked by gates or 'precharged' at different phases of
execution.

Bus names are depicted below as they are in Dr. Hansen's block diagram. They
may have expanded names, but I haven't been able to find any solid references
as to what they mean. The only instance I've found so far is an article from the
Visual6502 wiki archive on NESDev that suggests `SB` expands to "Special bus",
which would make sense considering the purpose of this bus but the article cites
no references for this name, and it hasn't appeared elsewhere in my research[1].

## The DB bus {#Ricoh_2A03_DB}

The DB bus (which I suppose expands to 'data bus') is connected to the data
output register, which eventually latches out to the Data pins on the CPU on
phi2 if `R/NOT W` is not asserted. It is connected to the accumulator, the CPU
status register, the B input register, the input data latch, and both of the
program counter registers. Pass MOSFETs allow it to bridge to the SB bus.

## The SB bus {#Ricoh_2A03_SB}

The SB bus connects to the ALU output, the A input register, the X and Y index
registers, the stack pointer register, and the accumulator. A set of pass
MOSFETs allows it to bridge to the ADH bus or the DB bus.

## The ADH bus {#Ricoh_2A03_ADH}

The ADH bus is connected to the input data latch and to the high bytes of the
program counter registers, as well as the high byte of the Address register.
This in turn is latched out to the high byte of the Address pins.

## The ADL bus {#Ricoh_2A03_ADL}

The ADL bus, like the ADH bus, is connected to the input data latch and to the
program counter registers and address register, except this time for the low
byte. Uniquely, it also feeds into the B input register and can accept output
from the adder hold register or the stack pointer. There are no gating MOSFETs
that connect this bus to any other bus.


[1]: https://www.nesdev.org/wiki/Visual6502wiki/6502_datapath_control_timing_fix