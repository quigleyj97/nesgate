library ieee;
use ieee.std_logic_1164.all;

--! @file ricoh_2a03.vhdl
--! @brief The Ricoh 2A03, the CPU of the NES and Famicom
--! @details A 2A03 is a @ref mos_6502 with its decimal mode cut out of the
--! masks. This entity instantiates the 6502 with `decimal_mode` set to `false`
--! and passes its pins straight through, so the 2A03's other parts (the APU,
--! the DMA controller and so on) can be added around it later.
--!
--! The pins, and how they behave, are the same as @ref mos_6502's. See that
--! entity for the clocks and the data pins.

entity ricoh_2a03 is
    port (
        --! @ref metaclock
        metaclock: in std_ulogic;
        --! @ref MOS_6502_Phi1
        phi1: in std_ulogic;
        --! @ref MOS_6502_Phi2
        phi2: in std_ulogic;
        --! @ref MOS_6502_Signal_RES (active-low pin)
        reset_pin_n_RES: in std_ulogic;
        --! @ref MOS_6502_Signal_IRQ (active-low pin)
        irq_pin_n_IRQ: in std_ulogic;
        --! @ref MOS_6502_Signal_NMI (active-low pin)
        nmi_pin_n_NMI: in std_ulogic;
        --! @ref MOS_6502_Signal_RDY
        ready_pin_RDY: in std_ulogic;
        --! The address pins, A0-A15 (see @ref mos_6502)
        address: out std_ulogic_vector(15 downto 0);
        --! The data pins, D0-D7, as driven by memory (see @ref mos_6502)
        data_in: in std_ulogic_vector(7 downto 0);
        --! The data pins, D0-D7, as driven by the CPU (see @ref mos_6502)
        data_out: out std_ulogic_vector(7 downto 0);
        --! @ref MOS_6502_Signal_R_NOT_W, the R/W pin
        read_not_write_R_NOT_W: out std_ulogic;
        --! The SYNC pin, high during an opcode fetch
        sync_SYNC: out std_ulogic
    );
end entity;

architecture rtl of ricoh_2a03 is
    component mos_6502 is
        generic (
            decimal_mode: boolean := true
        );
        port (
            metaclock: in std_ulogic;
            phi1: in std_ulogic;
            phi2: in std_ulogic;
            reset_pin_n_RES: in std_ulogic;
            irq_pin_n_IRQ: in std_ulogic;
            nmi_pin_n_NMI: in std_ulogic;
            ready_pin_RDY: in std_ulogic;
            address: out std_ulogic_vector(15 downto 0);
            data_in: in std_ulogic_vector(7 downto 0);
            data_out: out std_ulogic_vector(7 downto 0);
            read_not_write_R_NOT_W: out std_ulogic;
            sync_SYNC: out std_ulogic
        );
    end component;
    for cpu: mos_6502 use entity work.mos_6502;
begin
    --! The 6502 core, with its decimal mode cut out to match the 2A03
    cpu: mos_6502
        generic map (
            decimal_mode => false
        )
        port map (
            metaclock => metaclock,
            phi1 => phi1,
            phi2 => phi2,
            reset_pin_n_RES => reset_pin_n_RES,
            irq_pin_n_IRQ => irq_pin_n_IRQ,
            nmi_pin_n_NMI => nmi_pin_n_NMI,
            ready_pin_RDY => ready_pin_RDY,
            address => address,
            data_in => data_in,
            data_out => data_out,
            read_not_write_R_NOT_W => read_not_write_R_NOT_W,
            sync_SYNC => sync_SYNC
        );
end architecture;
