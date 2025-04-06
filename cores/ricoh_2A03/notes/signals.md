
# Signals {#Ricoh_2A03_Signals}

The circuitry of the 6502 is controlled by 62 signals from the instruction
decoder, which enables and disables various parts of the CPU at different phases
of execution. They are presented here in linear order as depicted by Dr.
Hansen's block diagram, and the index of each signal in this list corresponds to
the index of that signal in the `control_signals` inputs that are commonly used
by the project

## Data latch control signals

### `DL/DB` Data Input Latch DB Bus Output Enable {#Ricoh_2A03_Signal_DL_DB}
### `DL/ADL` Data Input Latch ADL Bus Output Enable {#Ricoh_2A03_Signal_DL_ADL}
### `DL/ADH` Data Input Latch ADH Bus Output Enable {#Ricoh_2A03_Signal_DL_ADH}

## Uncategorized

### `0/ADH0` {#Ricoh_2A03_Signal_0_ADH0}
### `0/ADH(1-7)` {#Ricoh_2A03_Signal_0_ADH_1_7}
### `ADH/ABH` {#Ricoh_2A03_Signal_ADH_ABH}
### `ADL/ABL` {#Ricoh_2A03_Signal_ADL_ABL}
### `PCL/PCL` {#Ricoh_2A03_Signal_PCL_PCL}
### `ADL/PCL` {#Ricoh_2A03_Signal_ADL_PCL}
### `I/PC` {#Ricoh_2A03_Signal_I_PC}
### `PCL/DB` {#Ricoh_2A03_Signal_PCL_DB}
### `PCL/ADL` {#Ricoh_2A03_Signal_PCL_ADL}
### `PCH/PCH` {#Ricoh_2A03_Signal_PCH_PCH}
### `ADH/PCH` {#Ricoh_2A03_Signal_ADH_PCH}
### `PCH/DB` {#Ricoh_2A03_Signal_PCH_DB}
### `PCH/ADH` {#Ricoh_2A03_Signal_PCH_ADH}
### `SB/ADH` {#Ricoh_2A03_Signal_SB_ADH}
### `SB/DB` {#Ricoh_2A03_Signal_SB_DB}
### `0/ADL0` {#Ricoh_2A03_Signal_0_ADL0}
### `0/ADL1` {#Ricoh_2A03_Signal_0_ADL1}
### `0/ADL2` {#Ricoh_2A03_Signal_0_ADL2}

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
