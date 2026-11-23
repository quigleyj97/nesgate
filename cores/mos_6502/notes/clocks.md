# Clocks {#MOS_6502_clocks}

The MOS 6502 relies on multiple, mutually exclusive clock signals that are
used in different phases of execution to light up different parts of the CPU.
This is a gate efficiency measure, and effectively allows the CPU to reuse
parts, like the ALU, for both user code and CPU operation.

## Phi1 {#MOS_6502_Phi1}

Some internal registers are latched in on phi1, like the instruction register,
the data output register, and the address bus registers.

## Phi2 {#MOS_6502_Phi2}

Most control signals are latched on in Phi2, as are most external memory modules
designed to work with the 6502- these infer a 'ready' signal from Phi2.

## Metaclock {#metaclock}

Usually, 6502s could generate these signals internally so long as it was given
a clock input. However, this core accepts a 'metaclock' signal that is not
present on the original hardware. This is down to synthesizability- while it's
perfectly reasonable electrically to have a sequential circuit driven by
multiple clock signals, synthesis tools like `yosys` can't make heads or tails
of any of it. For instance, with the following code:

```vhdl
process(load_from_a, load_from_b)
begin
    if rising_edge(load_from_a) then
        ...
    elsif rising_edge(load_from_b) then
        ...
    else
        ...
    end if
end process
```

GHDL will compile and run it, and it will simulate, but Yosys will throw a vague
error upon attempting to synthesize it as it doesn't support processes with
multiple clock signals (or 'pseudo' clock signals, as is the case here). To work
around this, while still trying to faithfully model the original hardware, such
circuitry is clocked with a higher-speed clock that allows the circuit to be
synthesized with reasonable equivalence to the original behavior.

Some latches feed other latches of the same phase through logic, as they do on
the real chip while both are open. With the metaclock, the second latch settles
a metaclock after the first, and the chains in the @ref interrupt_controller
and @ref random_logic_controller are up to two latches deep. So each phase must
last at least three metaclock cycles. The testbenches use four, the top level
uses seven, and the decoder proof checks every length from three to seven.
