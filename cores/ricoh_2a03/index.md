# Ricoh 2A03 Core {#Ricoh2A03}

This core implements the Ricoh 2A03, the CPU of the NES and Famicom. It's a
@ref mos_6502 with its decimal mode cut out of the masks, so @ref ricoh_2a03
instantiates the 6502 with `decimal_mode` set to `false` and passes its pins
straight through.

## Subpages

@subpage Rioch2A03_clocks
@subpage Ricoh2A03_signals

## Subunits

The 2A03 consists of several subunits beyond embedding the 6502 core, including
the APU, DMA controller, and a test region.

- [~] @ref ricoh_2a03
  - [~] @subpage Ricoh2A03_APU
    - [x] @ref aclk_generator
    - [x] @ref apu_counter
    - [ ] Length counter
    - [x] @ref frame_counter
    - [x] @ref length_decoder
    - [ ] Square channel
    - [ ] Triangle channel
    - [ ] Noise channel
    - [ ] Envelope unit
    - [ ] DPCM channel
  - [ ] DMA
    - [ ] DMA buffer
    - [ ] Sprite DMA controller
    - [ ] Address mux
  - [ ] Test region
    - [ ] Debug registers
    - [ ] IO ports
    - [ ] Register decoder

## Caveats

The APU does _not_ implement an internal DAC, diverging from chip behavior. This
is because FPGAs approach this differently, depending on the chip, board, and
intended output format (NTSC/PAL composite, GPDI video, GPDI plus audio, etc).

Additionally, changes specific to the PAL 2A07 are not yet implemented.
