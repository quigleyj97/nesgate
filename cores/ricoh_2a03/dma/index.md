# DMA {#Ricoh2A03_DMA}

The 2A03 has two DMAs, which share the address pins with the CPU and stall it
through its `RDY`:

- The sprite DMA (@ref sprite_dma), started by a write to `$4014`, copies a
  page of memory to the PPU's `$2004`. It stalls the CPU for 513 or 514
  cycles.
- The DMC's sample fetches, which @ref dpcm_channel makes itself, one byte at
  a time. Each stalls the CPU for 3 or 4 cycles, and pauses the sprite DMA if
  one is running.

@ref address_multiplexer picks who drives the address pins, and
@ref dma_buffer holds the byte the sprite DMA is copying, and decides which
way the data and R/W pins point.

Both DMAs only start during a CPU read cycle, because the 6502 ignores `RDY`
while it writes.
