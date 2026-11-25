# Ricoh 2A03 Core {#Ricoh2A03}

This core implements the Ricoh 2A03, the CPU of the NES and Famicom. It's a
@ref mos_6502 with its decimal mode cut out of the masks, so @ref ricoh_2a03
instantiates the 6502 with `decimal_mode` set to `false` and passes its pins
straight through.

The rest of the 2A03 (the APU, and the DMA controller) isn't implemented yet.
They'll be added to this core around the 6502.

Reference: @ref ricoh_2a03
