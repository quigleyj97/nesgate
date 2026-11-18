# The 6502 Arithmetic Logic Unit {#Ricoh2A03_ALU}

## Formal verification

@ref mos_6502_alu, the combinational part of the ALU, is formally proven to
behave as follows for every possible input: any A and B, either carry in,
either value of `DAA`, and any combination of operation enables, including
several at once.

- **Carry out (`ACR`)** is always the carry out of A + B + carry in,
  whichever operation is selected.
- **Overflow (`AVR`)** is always set exactly when A + B + carry in,
  read as signed numbers, falls outside -128 to 127.
- **Half carry (`HC`)** is always 0.
- **Result**:
  - `ORS` gives A OR B.
  - `EORS` gives A XOR B.
  - `ANDS` gives A AND B.
  - `SUMS` gives the low 8 bits of A + B + carry in.
  - `SRS` gives (A AND B) shifted right by one, with 0 shifted into bit 7.
  - With no operation enabled, the result is 0.
- **Several operations at once:** if more than one is enabled, the first one
  in the order `ORS`, `EORS`, `ANDS`, `SUMS`, `SRS` wins.
- **`DAA`** has no effect on any output.

Cover checks confirm that each of these cases actually comes up, so none of
the properties is passing trivially: every operation, a carry, a positive
and a negative overflow, a shift where the AND mask changes the result,
several operations enabled at once, and sums with `DAA` both set and clear.

### Not verified

- The rest of the ALU: @ref logic_core, the A and B input registers, the
  adder hold register, and the latching of `ACR` and `AVR` on Phi2. Clocked
  behavior isn't covered at all; the proof only looks at one instant.
- Decimal mode. The proof only confirms that `DAA` is ignored, which matches
  this implementation (see the to-do list below), not a real 6502 in decimal
  mode.
- That `HC` matches the real chip. The proof only confirms the current
  placeholder of a constant 0.
- What the real chip does when several operations are enabled at once. The
  priority order is this implementation's choice; on the real chip the
  outputs may simply be wired together (see @ref Ricoh2A03_ALU_HC).
- Rotates. The ALU only shifts in a 0; the random logic supplies the carry
  for `ROR`.
- Inputs other than 0 and 1 (`'X'`, `'U'`, `'Z'`). The proof runs on the
  synthesized netlist, where those don't exist.
- The properties are checked against the textbook definitions of each
  operation, not against the real chip's transistor netlist.

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
read when using a 3-byte addressing mode when a page cross happens).

Like `AVR`, it's latched during Phi2, along with the adder hold register, so
it holds the carry of the last operation while the A and B input registers
load the next one during Phi1. @ref logic_core holds the latches.

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
