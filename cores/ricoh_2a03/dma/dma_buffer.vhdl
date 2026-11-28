library ieee;
use ieee.std_logic_1164.all;

--! @file
--! @brief The sprite DMA buffer, and the data and R/W pins' direction control
--! @details The buffer is a latch on the internal data bus, open during every
--! Phi2, so it always holds the last byte on the bus. While the
--! @ref sprite_dma writes to `$2004` (@ref Ricoh_2A03_Signal_SPR_PPU), it
--! drives that byte back onto the bus, which is the byte the DMA read in the
--! cycle before.
--!
--! The same circuit makes the pin controls:
--!
--! - `RW`, for the R/W pin: the CPU's R/W, pulled low while the DMA writes.
--! - `RD`: the data pins are inputs. It's `RW`. When it's low, the internal
--!   data bus drives the pins.
--! - `WR`: the data pins don't drive the internal data bus. It's set during
--!   writes, and during reads of `$4015` or a debug read
--!   (@ref Ricoh_2A03_Signal_DBGRD). Those reads come from inside the chip,
--!   so the bits they don't drive keep whatever the bus last held. That's
--!   why bit 5 of `$4015` reads back the high byte of its address.
--!
--! The buffer latch is sampled on the @ref metaclock while Phi2 is high.
entity dma_buffer is
    port(
        --! @ref MOS_6502_Phi2
        phi2: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_SPR_PPU
        write_ppu_SPR_PPU: in std_ulogic;
        --! The CPU's @ref MOS_6502_Signal_R_NOT_W
        read_not_write_R_NOT_W: in std_ulogic;
        --! `R4015`, from the @ref register_decoder
        read_R4015: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_DBGRD
        debug_read_DBGRD: in std_ulogic;
        --! The internal data bus (@ref Ricoh_2A03_DB)
        bus_DB_in: in std_ulogic_vector(7 downto 0);
        --! Drives @ref Ricoh_2A03_DB during `SPR/PPU`, all ones (released)
        --! otherwise
        bus_DB_out: out std_ulogic_vector(7 downto 0);
        --! `RW`, to the R/W pin
        read_not_write_RW: out std_ulogic;
        --! `RD`: the data pins are inputs
        pins_input_RD: out std_ulogic;
        --! `WR`: the data pins don't drive the internal data bus
        pins_isolated_WR: out std_ulogic;
        --! @ref metaclock
        metaclock: in std_ulogic
    );
end entity dma_buffer;

architecture rtl of dma_buffer is
    --! The buffer latch
    signal buffer_latch: std_ulogic_vector(7 downto 0) := (others => '0');
    signal RW: std_ulogic;
begin
    process(metaclock)
    begin
        if rising_edge(metaclock) then
            if phi2 = '1' then
                buffer_latch <= bus_DB_in;
            end if;
        end if;
    end process;

    RW <= read_not_write_R_NOT_W and not write_ppu_SPR_PPU;
    read_not_write_RW <= RW;
    pins_input_RD <= RW;
    pins_isolated_WR <= read_R4015 or debug_read_DBGRD or not RW;
    bus_DB_out <= buffer_latch when write_ppu_SPR_PPU = '1' else (others => '1');
end architecture rtl;
