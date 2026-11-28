# Signals {#Ricoh_2A03_Signals}

The signals that connect the 2A03's parts, grouped by the part that makes
them. The real chip keeps many of them active-low (`/ACLK2`, `/LFO1`,
`/R4015`, `/DMCAB` and so on). This core keeps them all active-high, like the
6502 core's control signals, and names them without the slash.

Where Visual 2A03 has a node for a signal, it's listed, since its netlist is
the easiest way to check the real chip's behaviour.

## Pins and buses

### `RES` Reset {#Ricoh_2A03_Signal_RES}

The `/RES` pin, inverted. It resets most of the APU's counters and flip-flops,
as well as the CPU (@ref MOS_6502_Signal_RES). The channels' registers aren't
reset. Visual 2A03: node 10057 `_res`.

### `DBG` Test mode {#Ricoh_2A03_Signal_DBG}

The DBG pin. While it's high, the @ref register_decoder decodes the test mode
registers at `$4018`-`$401A` (see @ref debug_registers). Retail consoles tie it
low. Visual 2A03: node 10946 `dbg_en`.

### `DB` Internal data bus {#Ricoh_2A03_DB}

The bus the CPU's data pins, the 2A03's data pins and every register share.
As in the 6502's datapath, each driver has its own signal, all ones when
released, and the bus is their AND. Bits nothing drives keep what the bus last
held, like the real bus's charge (see @ref ricoh_2a03). Visual 2A03: `_db0`-`_db7`.

### `RDY` CPU ready {#Ricoh_2A03_Signal_RDY}

The CPU's @ref MOS_6502_Signal_RDY, from the @ref sprite_dma: low while a
sprite DMA is pending or running, or while the DMC isn't ready
(@ref Ricoh_2A03_Signal_DMCRDY). The 2A03 has no `RDY` pin. Visual 2A03: node
10758 `rdy`.

### `INT` APU interrupt {#Ricoh_2A03_Signal_INT}

The frame interrupt ORed with @ref Ricoh_2A03_Signal_DMCINT, from the
@ref frame_counter. It's ORed into the CPU's `/IRQ` along with the `/IRQ` pin.
Visual 2A03: node 10775 `irq_internal`.

## Clocks

### `ACLK1` APU clock, first phase {#Ricoh_2A03_Signal_ACLK1}

High during the Phi1 of the first CPU cycle of each APU cycle. See
@ref Ricoh_2A03_clocks. Visual 2A03: node 11434 `apu_clk1`.

### `ACLK2` APU clock, second phase {#Ricoh_2A03_Signal_ACLK2}

High during the Phi1 of the second CPU cycle of each APU cycle. The chip
distributes it inverted, as `/ACLK2`, and inverts it back where it's used.
Visual 2A03: node 10533 `apu_/clk2`.

### `LFO1` Quarter frame {#Ricoh_2A03_Signal_LFO1}

A pulse during ACLK2, four times a frame, from the @ref frame_counter. It
clocks the envelopes and the triangle's linear counter. Visual 2A03: node
10293 `frm_quarter`.

### `LFO2` Half frame {#Ricoh_2A03_Signal_LFO2}

A pulse during ACLK2, twice a frame, from the @ref frame_counter. It clocks
the sweeps and the length counters. Visual 2A03: node 10563 `frm_half`.

## Register decoder signals

### `REGRD` Register read {#Ricoh_2A03_Signal_REGRD}

The CPU is reading `$4000`-`$401F`, decoded from the CPU's own address bus.

### `REGWR` Register write {#Ricoh_2A03_Signal_REGWR}

The CPU is writing `$4000`-`$401F`, decoded from the CPU's own address bus.

### `W40xx` Register writes {#Ricoh_2A03_Signal_W40xx}

One strobe per writable register (`W4000`-`W4017`, and `W401A` in test mode),
high during Phi2 of a write to it. Visual 2A03: nodes `w4000`-`w401a`.

### `R40xx` Register reads {#Ricoh_2A03_Signal_R40xx}

One strobe per readable register (`R4015`-`R4017`, and `R4018`-`R401A` in test
mode), high for the whole of a read of it. `R4016` and `R4017` go out through
the `/IN0` and `/IN1` pins. Visual 2A03: nodes `/r4015`-`/r401a`.

### `DBGRD` Debug read {#Ricoh_2A03_Signal_DBGRD}

A read of `$4000`-`$401F` while @ref Ricoh_2A03_Signal_DBG is high. It stops
the data pins driving the internal bus. Visual 2A03: node 10839.

## Channel signals

### `xx_LC` Length counter carry {#Ricoh_2A03_Signal_xx_LC}

`SQA_LC`, `SQB_LC`, `TRI_LC` and `RND_LC`: the carry into each channel's
@ref length_counter, which is the channel's halt bit, inverted. While it's
low, the length counter holds. Visual 2A03: nodes `sq0_len_reload`,
`sq1_len_reload`, `tri_len_reload` and `noi_len_reload`.

### `NOxx` Length counter finished {#Ricoh_2A03_Signal_NOxx}

`NOSQA`, `NOSQB`, `NOTRI` and `NORND`: the channel's length counter has
finished, or the channel is disabled in `$4015`. It silences the channel.
Visual 2A03: nodes `sq0_silence`, `sq1_silence`, `tri_silence` and
`noi_silence`.

### `LOCK` Debug lock {#Ricoh_2A03_Signal_LOCK}

Set by bit 7 of a test mode write to `$401A`. It freezes the channels so their
outputs can be read back through `$4018`-`$401A`: the squares and noise output
their volume all the time, and the triangle and DMC stop stepping. Visual
2A03: node 10658 `snd_halt`.

## DMA signals

### `DMCAB` DMC owns the address bus {#Ricoh_2A03_Signal_DMCAB}

The @ref dpcm_channel is fetching a sample byte this cycle, so the
@ref address_multiplexer puts its address on the pins. The chip's signal is
active-low, `/DMCAB`. Visual 2A03: node 11411 `/ab_use_pcm`.

### `RUNDMC` DMC running {#Ricoh_2A03_Signal_RUNDMC}

The DMC is fetching, so the @ref sprite_dma pauses. Visual 2A03: node 11515.

### `DMCRDY` DMC ready {#Ricoh_2A03_Signal_DMCRDY}

Low from when the DMC requests a fetch until the fetch is done. It stalls the
CPU through @ref Ricoh_2A03_Signal_RDY. Visual 2A03: node 11483
`pcm_dma_/rdy`.

### `DMCINT` DMC interrupt {#Ricoh_2A03_Signal_DMCINT}

The DMC's interrupt flag, while its IRQ is enabled. Visual 2A03: node 10753
`pcm_irq_out`.

### `SPR/CPU` Sprite DMA read {#Ricoh_2A03_Signal_SPR_CPU}

The sprite DMA is reading a byte from memory this cycle, so the
@ref address_multiplexer puts its address on the pins. Visual 2A03: node
11099 `ab_use_spr_r`.

### `SPR/PPU` Sprite DMA write {#Ricoh_2A03_Signal_SPR_PPU}

The sprite DMA is writing the byte it read to `$2004` this cycle. The
@ref address_multiplexer puts `$2004` on the pins, the @ref dma_buffer drives
the byte onto the bus, and the R/W pin goes low. Visual 2A03: node 10764
`ab_use_spr_w`.
