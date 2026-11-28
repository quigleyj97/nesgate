library ieee;
use ieee.std_logic_1164.all;

--! @file
--! @brief The address multiplexer, which picks who drives the 2A03's
--! address pins
--! @details Each bit is a set of pass MOSFETs onto the pin's node, one per
--! source:
--!
--! | Select                             | Source                            |
--! |------------------------------------|-----------------------------------|
--! | @ref Ricoh_2A03_Signal_SPR_PPU     | `$2004`, the PPU's OAM data port  |
--! | @ref Ricoh_2A03_Signal_SPR_CPU     | The sprite DMA's address          |
--! | @ref Ricoh_2A03_Signal_DMCAB       | The DMC's sample address          |
--! | `CPU/AB`: none of the above        | The CPU's address bus             |
--!
--! The sprite DMA's selects are never on together, and the sprite DMA holds
--! both off while the DMC runs, so exactly one source drives the pins at a
--! time.
--!
--! The @ref register_decoder picks registers using this output, so while a
--! DMA owns the pins, a CPU read of `$4000`-`$401F` decodes the DMA's
--! register.
entity address_multiplexer is
    port(
        --! @ref Ricoh_2A03_Signal_SPR_CPU
        read_memory_SPR_CPU: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_SPR_PPU
        write_ppu_SPR_PPU: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_DMCAB
        dmc_address_bus_DMCAB: in std_ulogic;
        --! The DMC's sample address (`DMC_A`)
        dmc_address: in std_ulogic_vector(15 downto 0);
        --! The sprite DMA's address (`SPR_A`)
        sprite_address: in std_ulogic_vector(15 downto 0);
        --! The CPU's address bus (`CPU_A`)
        cpu_address: in std_ulogic_vector(15 downto 0);
        --! The address pins (`A`)
        pin_address: out std_ulogic_vector(15 downto 0)
    );
end entity address_multiplexer;

architecture rtl of address_multiplexer is
begin
    pin_address <= x"2004" when write_ppu_SPR_PPU = '1'
        else sprite_address when read_memory_SPR_CPU = '1'
        else dmc_address when dmc_address_bus_DMCAB = '1'
        else cpu_address;
end architecture rtl;
