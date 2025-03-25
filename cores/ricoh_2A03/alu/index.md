# The 6502 Arithmetic Logic Unit {#Ricoh2A03_ALU}

## To-do list

- [ ] Binary-Coded Decimal (BCD) support <b>\*1</b>

<b>\*1</b> BCD was never supported on the 2A03, but the way it was disabled is
reportedly by simply cutting traces in the production masks, and not by any
sort of redesign. So, on most production NESs, BCD support is in theory only 5
transistors away. [1] This may have a minimal impact on emulation accuracy, but
is part of the base 6502 and would be appropriate to implement in order to
support other platforms like the C64.

[1]: https://forums.nesdev.org/viewtopic.php?t=9813

## Components

- @ref logic_core - The main component of this subcore
- @ref a_input_register
- @ref b_input_register
- @ref adder_hold_register
- @ref mos_6502_alu

## Signals

### Inputs

The ALU is wired to the ADL, SB, and DB busses through input registers.
While it has no direct connection to the ADH bus, a set of passthrough MOSFETs
between the ADH and SB busses allows the ALU to conditionally read from that
bus.

### Output

#### `ACR` - ALU Carryout {#Ricoh2A03_ALU_ACR}

This signal maps to the Carry flag set on the status register, and is routed
there as well as used in a few other places (eg, to handle fixing the byte
read when using a 3-byte addressing mode when a page cross happens) 

#### `AVR` - ALU Overflow {#Ricoh2A03_ALU_AVR}

Similarly to the above, this signal is set when an overflow occurs during some
operations and maps to the Overflow status register flag.

#### `HC` - ALU Half Carry ?? {#Ricoh2A03_ALU_HC}

I have literally no clue what this does. Looking at block diagrams, this seems
to be used as an input to the BCD mode- there's an additional stage after the
ALU that's nominally used to correct the ALU output for BCD, and this signal
is routed there, so I imagine it might come from an individual half-adder-
maybe one for the MSB?

On block diagrams, I see the outputs all broken out by operation only to be
immediately joined together before being fed into the internal ALU register-
My guess is that the lines are simply wired together and that trying to enable
multiple operations at once will cause bus collisions, but I'm not sure about
that.
