# Subunit organization {#Ricoh2A03_code_organization}

The subunits I'm envisioning are:

- @subpage Ricoh2A03_ALU
    - [x] Arithmetic Logic Unit
    - [ ] Adder hold register
    - [ ] A and B input registers
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
    - [ ] Address Bus registers
- Ricoh2A03_Register_File
    - [ ] X and Y index registers
    - [ ] Status register
- Ricoh2A03_Databus_Interface
    - [ ] Input data latch
    - [ ] Data bus tristate buffer
    - [ ] Data out register
- @ref mos_6502
    - [ ] SB bus
    - [ ] DB bus
    - [ ] ADL bus
    - [ ] ADH bus
    - [ ] Precharge and pass MOSFETs