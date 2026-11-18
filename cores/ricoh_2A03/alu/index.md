# The 6502 Arithmetic Logic Unit {#Ricoh2A03_ALU}

## Formal verification

Each subunit of the ALU has its own SymbiYosys proof in `proofs/`, and
@ref logic_core has one more that checks them wired together. `./formal` runs
them all. Every proof has two tasks: `prove`, which shows that the
properties hold, and `cover`, which shows that every interesting case can
actually happen, so no property passes trivially.

The clocked proofs are unbounded (`abc pdr`), so they hold after any number
of steps, not only the first few. For every port that can drive a bus,
the proof applies the same `tribuf -merge` and precharge techmap that `synth`
uses (see @ref techmaps), so a disabled port reads all ones, the same as an
undriven, precharged bus.

| Subunit | Harness | Clocking |
|---|---|---|
| @ref mos_6502_alu | `alu_formal.sv` | combinational, one instant |
| @ref a_input_register | `a_input_register_formal.sv` | metaclock only |
| @ref b_input_register | `b_input_register_formal.sv` | metaclock only |
| @ref adder_hold_register | `adder_hold_register_formal.sv` | `multiclock on`: the rising edge of `load` |
| @ref logic_core | `logic_core_formal.sv` | `multiclock on`: the metaclock and Phi2, each changing freely |

### mos_6502_alu

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

### a_input_register

On every metaclock edge, the output becomes:

- the SB input, if `SB/ADD` was high,
- otherwise 0, if `0/ADD` was high (`SB/ADD` wins when both are high),
- otherwise the value it already held.

It powers up as 0.

### b_input_register

On every metaclock edge, the output becomes:

- the DB input inverted, if `NOT(DB)/ADD` was high,
- otherwise the DB input, if `DB/ADD` was high,
- otherwise the ADL input, if `ADL/ADD` was high,
- otherwise the value it already held.

When several loads are high, the first one in that order wins. It powers up
as 0.

### adder_hold_register

- On each rising edge of `load`, the register takes the value of `data_in`
  from just before the edge. At any other time it holds that value, even
  while `load` stays high and `data_in` changes.
- `ADD/SB(0-6)`, `ADD/SB(7)` and `ADD/ADL` each put the held value on their
  own bits, independently of one another. A port that isn't enabled reads
  all ones (precharged).
- It powers up as 0.

The proof assumes `load` starts low, so the first step is never treated
as an edge.

### logic_core

This proof checks the whole ALU path from the bus inputs to the bus outputs
and flags, against a model built from the same definitions as the proofs
above:

- The A and B input registers load on the metaclock, as above.
- The adder hold register takes the ALU result (computed from the A and B
  registers and the operation and carry controls) on each rising edge of
  Phi2, and drives SB and ADL as above.
- `ACR` and `AVR` take the ALU's carry and overflow on each metaclock edge
  while Phi2 is high, and hold them otherwise.
- `HC` is always 0.

The metaclock and Phi2 are independent inputs here, so the proof covers
any timing of the two, including ones a real clock generator never produces,
and not only real Phi1/Phi2 cycles. The A and B registers aren't outputs, so
they're only checked through their effect on the outputs. Cover checks walk
complete operations through the core: 0x7F + 0x01 overflowing to 0x80 on SB,
a carry out onto ADL, `ROR`'s split of `ADD/SB(0-6)` from `ADD/SB(7)`, and the
hold register and flags keeping their values while their inputs change.

The proof assumes both clocks start low.

### Not verified

- What a real chip does when two clock edges arrive on the same formal step.
  The proofs use the netlist's behavior, where every register samples its
  inputs from just before the edge.
- That a disabled port is high impedance (`'Z'`) rather than driving 0xFF.
  With the precharge techmap, the two read the same, so the proofs can only
  show that a disabled port reads all ones. The cocotb testbenches check for
  `'Z'`.
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
