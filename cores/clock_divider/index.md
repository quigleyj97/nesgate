# Clock Divider {#ClockDivider}

@ref clock_divider divides its input clock by `2 * divide_by`: its output
starts low and toggles on every `divide_by`-th rising edge of the input. The
top level (`targets/ulx3s_85k.vhdl`) uses it to make the CPU's two phases from
the @ref metaclock: Phi2 is the output and Phi1 its inverse, so each phase
lasts `METACLOCKS_PER_PHASE` metaclock cycles.

## Formal verification

`proofs/clock_divider_formal.sv` checks the divider on every rising edge of its
input clock, with an unbounded proof (`abc pdr`):

- The output powers up low.
- It never toggles before it has held its level through `divide_by` input
  edges, and never holds it any longer.

Together, these mean that after `n` input edges the output is
`floor(n / divide_by) mod 2`, so each half of its period lasts exactly
`divide_by` input edges. Cover checks confirm that the output rises, falls,
and rises again, so a whole period actually happens.

GHDL elaborates generics away, so the proof can't cover every `divide_by` at
once. `formal_check` synthesizes one netlist per divisor (see the core's
`formal` script), and `proofs/clock_divider.sby` has a prove and a cover task
for each:

| `divide_by` | Why |
|---|---|
| 1 | The smallest divisor: the counter has a single value, and the output toggles on every edge |
| 2 | The default |
| 3 | The fewest metaclocks per phase the CPU allows (see @ref Ricoh_2A03_clocks) |
| 7 | The top level's `METACLOCKS_PER_PHASE` |
| 8 | A power of two, where the counter uses every value of its bits |

To check another divisor, add it to both lists.

### Not verified

- Divisors other than the ones above.
- That Phi1 and Phi2 never overlap at the top level. The top level makes Phi1
  by inverting the divider's output, outside this core.
