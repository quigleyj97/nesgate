# Subunit organization {#Ricoh2A03_code_organization}

![Block diagram of everything currently implemented](./implemented.drawio.svg)

- [~] @subpage Ricoh2A03_ALU
    - [x] @ref mos_6502_alu
    - [x] @ref adder_hold_register
    - [x] @ref a_input_register
    - [x] @ref b_input_register
    - [ ] (todo) BCD Corrector
- [x] @subpage Ricoh2A03_Instruction_Decoder
    - [x] @ref predecode_register
    - [x] @ref predecode_logic
    - [x] @ref instruction_register
    - [x] @ref timing_generator - T0-T7 timing generation logic
    - [x] @ref decoder_rom - the 130-line instruction decoder ROM
    - [x] @ref interrupt_controller - NMI, IRQ and reset handling, and the BRK sequence
    - [x] @ref ready_controller - ready, WR, ReadyPhi1 and PRDY
    - [x] @ref random_logic_controller - the random logic and dispatcher: every control command, instruction completion, PC increment, opcode fetch and branches
- [x] @ref MOS_6502_PC_Registers
    - [x] @ref program_counter_low - PCLS, PCL and increment logic
    - [x] @ref program_counter_high - PCHS, PCH and increment logic
- [~] @subpage MOS_6502_Datapath
    - [x] @ref index_register - X and Y index registers
    - [x] @ref accumulator
    - [~] @ref mos_6502_datapath
    - [x] Address Bus registers
    - [x] @ref stack_pointer
    - [x] @ref bus_multiplexer - precharge, open drain and pass MOSFETs
    - [x] @ref status_register
    - [x] @ref data_input_latch
    - [x] @ref data_output_latch
