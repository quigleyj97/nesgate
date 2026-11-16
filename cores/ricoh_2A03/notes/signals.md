
# Signals {#Ricoh_2A03_Signals}

The circuitry of the 6502 is controlled by 62 signals from the instruction
decoder, which enables and disables various parts of the CPU at different phases
of execution. They are grouped here by the part of the CPU they control, along
with a few signals that don't come from the decoder.

## Data latch control signals

### `DL/DB` Data Input Latch DB Bus Output Enable {#Ricoh_2A03_Signal_DL_DB}
### `DL/ADL` Data Input Latch ADL Bus Output Enable {#Ricoh_2A03_Signal_DL_ADL}
### `DL/ADH` Data Input Latch ADH Bus Output Enable {#Ricoh_2A03_Signal_DL_ADH}

## Address bus register signals

### `ADH/ABH` Load ABH from ADH bus {#Ricoh_2A03_Signal_ADH_ABH}
### `ADL/ABL` Load ABL from ADL bus {#Ricoh_2A03_Signal_ADL_ABL}

## Bus multiplexer signals

These control the open drain and pass MOSFETs, which @ref bus_multiplexer
models along with the precharge.

### `SB/DB` Join SB and DB buses {#Ricoh_2A03_Signal_SB_DB}

Turns on the pass MOSFETs between SB and DB, so they act as a single bus.
Either side can drive it.

### `SB/ADH` Join SB and ADH buses {#Ricoh_2A03_Signal_SB_ADH}

Turns on the pass MOSFETs between SB and ADH, so they act as a single bus.
Either side can drive it.

### `0/ADL0` Pull ADL bit 0 low {#Ricoh_2A03_Signal_0_ADL0}
### `0/ADL1` Pull ADL bit 1 low {#Ricoh_2A03_Signal_0_ADL1}
### `0/ADL2` Pull ADL bit 2 low {#Ricoh_2A03_Signal_0_ADL2}

Together with the precharge, these form the low byte of the interrupt vectors:
`0xFA` (NMI), `0xFC` (reset) and `0xFE` (IRQ/BRK).

### `0/ADH0` Pull ADH bit 0 low {#Ricoh_2A03_Signal_0_ADH0}
### `0/ADH(1-7)` Pull ADH bits 1-7 low {#Ricoh_2A03_Signal_0_ADH_1_7}

Together, these address the zero page (`0x00`). `0/ADH(1-7)` alone addresses
the stack page (`0x01`).

## Program counter signals

These control @ref program_counter_low and @ref program_counter_high (see
@ref MOS_6502_PC_Registers). The select register loads (`PCL/PCL`, `ADL/PCL`,
`PCH/PCH`, `ADH/PCH`) are only active during phi1, and
@ref mos_6502_datapath gates them with phi1. `I/PC` and the bus output enables
are active in both phases.

### `PCL/PCL` Refresh PCL select register from PCL {#Ricoh_2A03_Signal_PCL_PCL}

Loads PCLS from PCL, so that PCL keeps its value (plus the increment, if
`I/PC` is asserted) on the next phi2. The random control logic asserts this
whenever it doesn't assert `ADL/PCL`.

### `ADL/PCL` Load PCL select register from ADL bus {#Ricoh_2A03_Signal_ADL_PCL}

Loads PCLS from the ADL bus, e.g. to jump or to load a vector.

### `I/PC` Increment program counter {#Ricoh_2A03_Signal_I_PC}

Increments the program counter on the next phi2. PCL increments directly, and
PCH increments on @ref Ricoh_2A03_PCLC. The real chip uses this signal
active-low, as `#1/PC`.

### `PCL/DB` Enable PCL output to DB bus {#Ricoh_2A03_Signal_PCL_DB}
### `PCL/ADL` Enable PCL output to ADL bus {#Ricoh_2A03_Signal_PCL_ADL}
### `PCH/PCH` Refresh PCH select register from PCH {#Ricoh_2A03_Signal_PCH_PCH}

Loads PCHS from PCH, so that PCH keeps its value (plus the carry from PCL) on
the next phi2. The random control logic asserts this whenever it doesn't assert
`ADH/PCH`.

### `ADH/PCH` Load PCH select register from ADH bus {#Ricoh_2A03_Signal_ADH_PCH}

Loads PCHS from the ADH bus, e.g. to jump or to load a vector.

### `PCH/DB` Enable PCH output to DB bus {#Ricoh_2A03_Signal_PCH_DB}
### `PCH/ADH` Enable PCH output to ADH bus {#Ricoh_2A03_Signal_PCH_ADH}

The program counter's increment logic also generates two carries internally,
which don't come from the decoder:

### `PCLC` Program counter low carry {#Ricoh_2A03_PCLC}

The carry out of the PCL increment logic, which increments PCH. It's set when
`I/PC` is asserted and PCLS is `0xFF`.

### `PCHC` Program counter high nibble carry {#Ricoh_2A03_PCHC}

PCH's increment logic is split into two nibbles, as in Hanson's block diagram.
PCHC is the carry from the low nibble into the high nibble, set when PCLC is
set and the low nibble of PCHS is `0xF`. There's no carry out of the high
nibble, so the program counter wraps from `0xFFFF` to `0x0000`.

## Stack pointer signals

### `S/ADL` Enable S register output to ADL bus {#Ricoh_2A03_Signal_S_ADL}
### `SB/S` Load value into S register from SB bus {#Ricoh_2A03_Signal_SB_S}
### `S/S` Refresh S register value {#Ricoh_2A03_Signal_S_S}

Note - this signal is not implemented by this core. It appears to be necessary
for the actual register, as-implemented, to keep it's value valid between many
CPU cycles (since it might be a long time between reads/writes), but that is not
necessary on FPGA fabric.

### `S/SB` Enable S register output to the SB bus {#Ricoh_2A03_Signal_S_SB}

## ALU Signals

### `NOT(DB)/ADD` ALU B Register Load Inverted {#Ricoh_2A03_Signal_NOT_DB_ADD}

Load the inverse of a word from the DB bus into the B input register of the ALU

### `DB/ADD` ALU B Register Load {#Ricoh_2A03_Signal_DB_ADD}

Load a word from the DB bus into the B input register of the ALU

### `ADL/ADD` ALU B Register Load ADL Bus {#Ricoh_2A03_Signal_ADL_ADD}

Load a word from the ADL bus into the B input register of the ALU

### `I/ADDC` - ALU Carry-in Input {#Ricoh2A03_ALU_IADDC}

Control line for carry-in

### `DAA` - ALU Decimal Mode Enable {#Ricoh2A03_ALU_DAA}

This controls whether the ALU operates in normal mode or in BCD

### `DSA` - ALU {#Ricoh2A03_DSA}

Unknown, related to BCD correction

### `SUMS` - ALU Summation Enable {#Ricoh2A03_ALU_SUMS}
### `ANDS` - ALU Logical AND Enable {#Ricoh2A03_ALU_ANDS}
### `EORS` - ALU Logical XOR Enable {#Ricoh2A03_ALU_EORS}

At least, exclusive is what I'm guessing the "E" in "EOR" expands to.

### `ORS` - ALU Logical OR Enable {#Ricoh2A03_ALU_ORS}
### `SRS` - ALU Shift Right Enable {#Ricoh2A03_ALU_SRS}

TBD: Is this a logical or arithmetic shift?

The 6502 supports instructions for both, and strangely while this only seems to
support right-shifts I know the CPU also has both arithmetic and logical left
shifts.

### `ADD/ADL` - Enable Adder Hold Register ADL Bus Output {#Ricoh2A03_ADD_ADL}
### `ADD/SB(0-6)` - Enable Adder Hold Register SB Bus Outpu, bits 0-6 {#Ricoh2A03_ADD_SB_0_6}
### `ADD/SB(7)` - Enable Adder Hold Register SB Bus Outpu, bit 7 {#Ricoh2A03_ADD_SB_7}
### `0/ADD` - Load 0s into the A input register {#Ricoh2A03_0_ADD}
### `SB/ADD` - Load from the SB bus into the A input register {#Ricoh2A03_SB_ADD}

## Register control signals 
### `SB/AC` - Load from SB bus into the accumulator {#Ricoh_Signal_SB_AC}

This is nominally routed through the BCD correction circuity, but this core
doesn't yet implement that, so the routing is direct.

### `AC/DB` - Enable Accumulator output to DB bus {#Ricoh_Signal_AC_DB}
### `AC/SB` - Enable Accumulator output to SB bus {#Ricoh_Signal_AC_SB}
### `SB/X` {#Ricoh_Signal_SB_X}
### `X/SB` {#Ricoh_Signal_X_SB}
### `SB/Y` {#Ricoh_Signal_SB_Y}
### `Y/SB` {#Ricoh_Signal_Y_SB}

## Processor Status Register Signals

### `P/DB` Enable DB bus output for P register {#Ricoh_Signal_P_DB}
### `DB0/C` Set C to the value of DB(0) {#Ricoh_Signal_DB0_C}
### `IR5/C` Set C to the value of IR5 bit {#Ricoh_Signal_IR5_C}
### `ACR/C` Set C to the value of ACR {#Ricoh_Signal_ACR_C}
### `DB1/Z` Set Z to the value of DB(1){#Ricoh_Signal_DB1_Z}
### `DBZ/Z` Set Z to the value of DBZ {#Ricoh_Signal_DBZ_Z}
### `DB2/I` Set I to the value of DB(2) {#Ricoh_Signal_DB2_I}
### `IR5/I` Set I to the value of IR5 {#Ricoh_Signal_IR5_I}
### `DB3/D` Set D to the value of DB(3) {#Ricoh_Signal_DB3_D}
### `IR5/D` Set D to the value of IR5 {#Ricoh_Signal_IR5_D}
### `DB6/V` Set V to the value of DB(6) {#Ricoh_Signal_DB6_V}
### `AVR/V` Set V to the value of AVR {#Ricoh_Signal_AVR_V}
### `1/V` Set V to the value of 1/V {#Ricoh_Signal_1_V}

Todo: There's a related signal 0/V that isn't always labelled... does this need
implementation?

### `DB7/N` Set N to the value of DB(7) {#Ricoh_Signal_DB7_N}

## External CPU Signals

### `R/NOT W` Read/write signal {#Ricoh_Signal_R_NOT_W}

When asserted, the CPU wants to execute a bus read on the next Phi2. Conversely,
when not asserted, the CPU wants to execute a write on the next Phi2.

## Predecode signals

These signals come from or go to the predecode logic, and aren't produced by
the decoder ROM. See
@ref Ricoh2A03_Instruction_Decoder.

### `0/IR` Inject BRK into the instruction register {#Ricoh_2A03_Signal_0_IR}

Forces the predecoded opcode to `0x00` (BRK). Interrupts use this to start the
BRK sequence, since every interrupt mimics BRK with slight changes. It is
driven by the interrupt and dispatch logic.

### `TWOCYCLE` Two-cycle instruction {#Ricoh_2A03_Signal_TWOCYCLE}

Set when the predecoded opcode always completes in 2 cycles: an immediate
operand instruction, or a single-byte instruction other than a stack push or
pull. Used by the short cycle counter in the timing logic. The real chip
outputs this active-low, as `/TWOCYCLE`.

### `IMPLIED` Single-byte instruction {#Ricoh_2A03_Signal_IMPLIED}

Set when the predecoded opcode matches `XXXX10X0`, a single-byte instruction
with no operand. Used by the program counter increment logic. The real chip
outputs this active-low, as `/IMPLIED`.

## Instruction register signals

These signals control the @ref instruction_register, and aren't produced by the
decoder ROM. See @ref Ricoh2A03_Instruction_Decoder.

### `FETCH` Load the instruction register {#Ricoh_2A03_Signal_FETCH}

When asserted during @ref Ricoh_2A03_Phi1, loads the opcode from the
@ref predecode_logic into the @ref instruction_register. It is driven by the
dispatch logic on the first cycle of each instruction, and the instruction
register holds its value while it's deasserted.


## Timing signals

These signals come from or go to the @ref timing_generator, and aren't produced
by the decoder ROM. They tell the decoder ROM and the random logic which cycle
of an instruction the CPU is on. See @ref Ricoh2A03_Instruction_Decoder.

The real chip outputs `/T0`, `/T1X` and `/T2`-`/T5` active-low, and takes
`/ready` active-low. This core keeps them all active-high.

### `T0` Last cycle of an instruction {#Ricoh_2A03_Signal_T0}

Set on the last cycle of an instruction, which on the 6502 overlaps with
fetching the next opcode. It is set after @ref Ricoh_2A03_Signal_TRESX, or on
the second cycle of a @ref Ricoh_2A03_Signal_TWOCYCLE instruction, but never
during @ref Ricoh_2A03_Signal_T1. It stays set until
@ref Ricoh_2A03_Signal_T1X follows it.

### `T1` Opcode fetch cycle {#Ricoh_2A03_Signal_T1}

Set on the cycle that fetches an opcode, which is the first cycle of an
instruction. It is @ref Ricoh_2A03_Signal_TRES1, latched during
@ref Ricoh_2A03_Phi1. It also drives the external `SYNC` pin, and the dispatch
logic uses it to make @ref Ricoh_2A03_Signal_FETCH.

### `T1X` Cycle after T0 {#Ricoh_2A03_Signal_T1X}

Set on the cycle after @ref Ricoh_2A03_Signal_T0, which is normally the opcode
fetch cycle (@ref Ricoh_2A03_Signal_T1) of the next instruction. It ends `T0`.
The decoder ROM uses `T1X` rather than `T1`.

### `T2` Second cycle {#Ricoh_2A03_Signal_T2}
### `T3` Third cycle {#Ricoh_2A03_Signal_T3}
### `T4` Fourth cycle {#Ricoh_2A03_Signal_T4}
### `T5` Fifth cycle {#Ricoh_2A03_Signal_T5}

The extended cycle counter, a shift register that moves
@ref Ricoh_2A03_Signal_T1 along one stage per cycle. `T2` follows `T1`, `T3`
follows `T2`, and so on, until `TRES2` clears them. `TRES2` is
@ref Ricoh_2A03_Signal_TRESX, latched during @ref Ricoh_2A03_Phi1.

### `T6` First read-modify-write cycle {#Ricoh_2A03_Signal_T6}

Set on the cycle after one with both @ref Ricoh_2A03_Signal_SHIFT and
@ref Ricoh_2A03_Signal_MemOP set, during a read-modify-write instruction. A
read-modify-write instruction writes twice, first the unmodified value and then
the modified one. The R/W logic uses `T6` and @ref Ricoh_2A03_Signal_T7 to
switch the CPU to writing.

### `T7` Second read-modify-write cycle {#Ricoh_2A03_Signal_T7}

Set on the cycle after @ref Ricoh_2A03_Signal_T6. It also finishes the
instruction, through @ref Ricoh_2A03_Signal_TRESX.

### `ready` CPU ready {#Ricoh_2A03_Signal_ready}

Low while the CPU is stalled by the external `RDY` pin. It is latched during
@ref Ricoh_2A03_Phi2, so a stall holds from Phi2 through the next Phi1. While
it's low, the timing logic holds its current cycle, and the stalled cycle
repeats the one before it. The ready control logic makes it, and keeps it high
during write cycles, since the 6502 can only stall on reads. The real chip
calls it `/ready`, active-low.

### `TRES1` Reset the short cycle counter {#Ricoh_2A03_Signal_TRES1}

Starts @ref Ricoh_2A03_Signal_T1 on the next cycle, which begins the next
instruction. The instruction completion logic in the dispatcher makes it.

### `TRESX` Reset the cycle counters {#Ricoh_2A03_Signal_TRESX}

Set when an instruction is finishing. It starts @ref Ricoh_2A03_Signal_T0, and
clears @ref Ricoh_2A03_Signal_T2 through @ref Ricoh_2A03_Signal_T5 through
`TRES2`. The instruction completion logic in the dispatcher makes it. The real
chip outputs it active-low, as `#TRESX`.

### `SHIFT` Shift or rotate instruction {#Ricoh_2A03_Signal_SHIFT}

Set for the shift and rotate instructions, and for INC and DEC (decoder lines
106 and 107). The real chip outputs it active-low, as `/SHIFT`.

### `MemOP` Memory operand addressing {#Ricoh_2A03_Signal_MemOP}

Set by the decoder lines for the addressing cycles of instructions with a
memory operand (lines 111 and 122-125). Together with
@ref Ricoh_2A03_Signal_SHIFT, it starts the read-modify-write cycles. The real
chip outputs it active-low, as `/MemOP`.

## Decoder ROM signals

These signals come from or go to the @ref decoder_rom. See
@ref Ricoh2A03_Instruction_Decoder.

### Decoder lines {#Ricoh_2A03_Decoder_Lines}

The 130 outputs of the @ref decoder_rom, numbered 0-129 as in the decoder table.
Each line is set when the opcode in the @ref instruction_register matches its
mask, during its cycle (or any cycle, for lines marked `TX`). The random logic
combines them into the control signals on this page. The comments on
`decoder_masks` in the @ref decoder_rom list what each line matches.

A few lines have extra logic in the decoder area. Line 129 matches the stack
push/pull instructions, and only removes them from lines 83, 90 and 128. Line 73
(Branch T0, called `BR0` outside the decoder) is gated by
@ref Ricoh_2A03_Signal_PRDY. Line 128 (IMPL) also checks that `IR0` is 0.

The real chip outputs the lines active-low. This core keeps them active-high.

### `PRDY` Previous ready {#Ricoh_2A03_Signal_PRDY}

The external `RDY` pin, delayed by a chain of latches, so it says whether the
CPU was ready on the previous cycle. It gates decoder line 73 (Branch T0): if
the CPU wasn't ready when the previous instruction finished, the T0 cycle of a
conditional branch is skipped. The real chip calls it `/PRDY`, active-low.
