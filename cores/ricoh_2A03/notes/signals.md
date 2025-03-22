
# Signals {#Ricoh_2A0}

The circuitry of the 6502 is controlled by 62 signals from the instruction
decoder, which enables and disables various parts of the CPU at different phases
of execution. They are presented here in linear order as depicted by Dr.
Hansen's block diagram, and the index of each signal in this list corresponds to
the index of that signal in the `control_signals` inputs that are commonly used
by the project

## Uncategorized

### `DL/DB` {#Ricoh_2A03_Signal_DL/DB}
### `DL/ADL` {#Ricoh_2A03_Signal_DL/ADL}
### `DL/ADH` {#Ricoh_2A03_Signal_DL/ADH}
### `0/ADH0` {#Ricoh_2A03_Signal_0/ADH0}
### `0/ADH(1-7)` {#Ricoh_2A03_Signal_0/ADH(1-7)}
### `ADH/ABH` {#Ricoh_2A03_Signal_ADH/ABH}
### `ADL/ABL` {#Ricoh_2A03_Signal_ADL/ABL}
### `PCL/PCL` {#Ricoh_2A03_Signal_PCL/PCL}
### `ADL/PCL` {#Ricoh_2A03_Signal_ADL/PCL}
### `I/PC` {#Ricoh_2A03_Signal_I/PC}
### `PCL/DB` {#Ricoh_2A03_Signal_PCL/DB}
### `PCL/ADL` {#Ricoh_2A03_Signal_PCL/ADL}
### `PCH/PCH` {#Ricoh_2A03_Signal_PCH/PCH}
### `ADH/PCH` {#Ricoh_2A03_Signal_ADH/PCH}
### `PCH/DB` {#Ricoh_2A03_Signal_PCH/DB}
### `PCH/ADH` {#Ricoh_2A03_Signal_PCH/ADH}
### `SB/ADH` {#Ricoh_2A03_Signal_SB/ADH}
### `SB/DB` {#Ricoh_2A03_Signal_SB/DB}
### `0/ADL0` {#Ricoh_2A03_Signal_0/ADL0}
### `0/ADL1` {#Ricoh_2A03_Signal_0/ADL1}
### `0/ADL2` {#Ricoh_2A03_Signal_0/ADL2}
### `S/ADL` {#Ricoh_2A03_Signal_S/ADL}
### `SB/S` {#Ricoh_2A03_Signal_SB/S}
### `S/S` {#Ricoh_2A03_Signal_S/S}
### `S/SB` {#Ricoh_2A03_Signal_S/SB}
### `NOT(DB)/ADD` {#Ricoh_2A03_Signal_NOT(DB)/ADD}
### `DB/ADD` {#Ricoh_2A03_Signal_DB/ADD}
### `ADL/ADD` {#Ricoh_2A03_Signal_ADL/ADD}

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
### `ADD/SB(0-6)` - Enable Adder Hold Register SB Bus Outpu, bits 0-6{#Ricoh2A03_ADD_SB_0_6}
### `ADD/SB(0-6)` - Enable Adder Hold Register SB Bus Outpu, bit 7{#Ricoh2A03_ADD_SB_7}
### `0/ADD` - Load 0s into the A input register {#Ricoh2A03_0_ADD}
### `SB/ADD` - Load from the SB bus into the A input register {#Ricoh2A03_SB_ADD}

## Uncategorized 2

### `SB/AC` {#Ricoh_Signal_SB/AC}
### `AC/DB` {#Ricoh_Signal_AC/DB}
### `AC/SB` {#Ricoh_Signal_AC/SB}
### `SB/X` {#Ricoh_Signal_SB/X}
### `X/SB` {#Ricoh_Signal_X/SB}
### `SB/Y` {#Ricoh_Signal_SB/Y}
### `Y/SB` {#Ricoh_Signal_Y/SB}
### `P/DB` {#Ricoh_Signal_P/DB}
### `DB0/C` {#Ricoh_Signal_DB0/C}
### `IR5/C` {#Ricoh_Signal_IR5/C}
### `ACR/C` {#Ricoh_Signal_ACR/C}
### `DBI/Z` {#Ricoh_Signal_DBI/Z}
### `DBZ/Z` {#Ricoh_Signal_DBZ/Z}
### `DB2/I` {#Ricoh_Signal_DB2/I}
### `IR5/I` {#Ricoh_Signal_IR5/I}
### `DB3/D` {#Ricoh_Signal_DB3/D}
### `IR5/D` {#Ricoh_Signal_IR5/D}
### `DB6/V` {#Ricoh_Signal_DB6/V}
### `AVR/V` {#Ricoh_Signal_AVR/V}
### `I/V` {#Ricoh_Signal_I/V}
### `DB7/N` {#Ricoh_Signal_DB7/N}