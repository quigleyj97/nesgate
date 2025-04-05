# Subunit organization {#Ricoh2A03_code_organization}

![Block diagram of everything currently implemented](./implemented.drawio.svg)

- [~] @subpage Ricoh2A03_ALU
    - [x] @ref mos_6502_alu
    - [x] @ref adder_hold_register
    - [x] @ref a_input_register
    - [x] @ref b_input_register
    - [ ] (todo) BCD Corrector
- Ricoh2A03_Instruction_Decoder
    - [ ] Predecode register
    - [ ] Predecode logic
    - [ ] Instruction register
    - [ ] Timing generation logic
    - [ ] Instruction decoder ROM
    - [ ] Interrupt controller
    - [ ] Ready controller
- Ricoh2A03_Program_Counter
    - [ ] Program Counter Select registers
    - [ ] Program Counter registers
    - [ ] Program Counter increment logic
- [~] @subpage MOS_6502_Datapath
    - [x] @ref index_register - X and Y index registers
    - [x] @ref accumulator
    - [~] @ref mos_6502_datapath
    - [x] Address Bus registers
    - [ ] Stack pointer
    - [ ] Gate and charge MOSFETs
    - [x] @ref status_register
    - [x] @ref data_input_latch
    - [x] @ref data_output_latch
