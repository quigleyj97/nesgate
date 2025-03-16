# The 6502 Arithmetic Logic Unit {#Ricoh2A03_ALU}

## To-do list

- [ ] Binary-Coded Decimal (BCD) support <b>\*1</b>

<b>\*1</b> BCD was never supported on the 2A03, but the way it was disabled is
reportedly by simply cutting traces in the production masks, and not by any
sort of redesign. So, on most production NESs, BCD support is in theory only 5
transistors away. [1] This may have a minimal impact on emulation accuracy, but
is part of the base 6502 and would be appropriate to implement in order to
support other platforms like the C64.

## Signals

### ALU Output Signals

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

### ALU Control Signals

#### `DAA` - ALU Decimal Mode Enable {#Ricoh2A03_ALU_DAA}

This controls whether the ALU operates in normal mode or in BCD

#### `I/ADDC` - ALU Carry-in Input {#Ricoh2A03_ALU_IADDC}

Control line for carry-in

#### `SUMS` - ALU Summation Enable {#Ricoh2A03_ALU_SUMS}
#### `ANDS` - ALU Logical AND Enable {#Ricoh2A03_ALU_ANDS}
#### `EORS` - ALU Logical XOR Enable {#Ricoh2A03_ALU_EORS}

At least, exclusive is what I'm guessing the "E" in "EOR" expands to.

#### `ORS` - ALU Logical OR Enable {#Ricoh2A03_ALU_ORS}
#### `SRS` - ALU Shift Right Enable {#Ricoh2A03_ALU_SRS}

TBD: Is this a logical or arithmetic shift?

The 6502 supports instructions for both, and strangely while this only seems to
support right-shifts I know the CPU also has both arithmetic and logical left
shifts.

### Output

On block diagrams, I see the outputs all broken out by operation only to be
immediately joined together before being fed into the internal ALU register-
My guess is that the lines are simply wired together and that trying to enable
multiple operations at once will cause bus collisions, but I'm not sure about
that.

## References

[1]: https://forums.nesdev.org/viewtopic.php?t=9813