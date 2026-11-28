library ieee;
use ieee.std_logic_1164.all;

--! @file ricoh_2a03.vhdl
--! @brief The Ricoh 2A03, the CPU of the NES and Famicom
--! @details A 2A03 is a @ref mos_6502 with its decimal mode cut out of the
--! masks, plus the APU, a sprite DMA controller and some I/O ports, all on
--! the 6502's data bus. This entity wires them together:
--!
--! - The @ref aclk_generator divides the CPU's clocks into the APU's
--!   (@ref Ricoh_2A03_clocks).
--! - The @ref register_decoder turns reads and writes of `$4000`-`$401F`
--!   into strobes for the rest.
--! - The @ref frame_counter clocks the channels' envelopes, sweeps and
--!   length counters.
--! - Two @ref square_channel "square channels", a @ref triangle_channel, a
--!   @ref noise_channel and the @ref dpcm_channel "DMC" make the sound, with
--!   four @ref length_counter "length counters" and a @ref length_decoder.
--!   Their outputs are digital: the real chip's DAC is analog, so mixing is
--!   left to whatever drives the speaker.
--! - The @ref sprite_dma, @ref address_multiplexer and @ref dma_buffer let
--!   the sprite DMA and the DMC's sample fetches take over the address pins,
--!   stalling the CPU through its `RDY`.
--! - The @ref io_ports drive the `OUT0`-`OUT2` and `/IN0`-`/IN1` pins, and
--!   the @ref debug_registers add the test mode registers when DBG is high.
--!
--! **Clocks.** Like @ref mos_6502, Phi1 and Phi2 come from outside along
--! with the @ref metaclock, rather than from the real chip's divider of its
--! `CLK` pin, so this entity has no `CLK` or `M2` pin. Each phase must last at
--! least three metaclock cycles.
--!
--! **Data bus.** The internal data bus (@ref Ricoh_2A03_DB) connects the
--! CPU, the data pins and every register. Each of them drives its own signal,
--! all ones when released, and the bus is their AND, as in the 6502's
--! datapath. The data pins drive it during reads, except during reads the
--! chip answers itself (`$4015`, and debug reads). Then the bits nothing
--! drives keep what the bus last held, like the real bus's charge. That's
--! modeled by a keeper latch, which is sampled every metaclock and fills in
--! the floating bits.
--!
--! The data pins are split into `data_in` and `data_out`, as on
--! @ref mos_6502. `data_out` is the internal bus while the R/W pin is low,
--! and all ones otherwise.
--!
--! **Pins.** The real 2A03 has no `RDY` or `SYNC` pin: the DMA controllers
--! drive the CPU's `RDY`, and its `SYNC` isn't connected. `sync_SYNC` is kept
--! for testbenches, and is only high while the CPU owns the address pins.
--! During reset the real chip floats the address, R/W and I/O pins, which
--! this entity keeps driving.
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
        --! @ref MOS_6502_Signal_IRQ (active-low pin), ORed with the APU's
        --! interrupts
        irq_pin_n_IRQ: in std_ulogic;
        --! @ref MOS_6502_Signal_NMI (active-low pin)
        nmi_pin_n_NMI: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_DBG, the test mode pin. Low on retail
        --! consoles.
        debug_pin_DBG: in std_ulogic;
        --! The address pins, A0-A15, from the @ref address_multiplexer
        address: out std_ulogic_vector(15 downto 0);
        --! The data pins, D0-D7, as driven by memory
        data_in: in std_ulogic_vector(7 downto 0);
        --! The data pins, D0-D7, as driven by the 2A03. All ones unless the
        --! R/W pin is low.
        data_out: out std_ulogic_vector(7 downto 0);
        --! The R/W pin: low while the CPU or the sprite DMA writes
        read_not_write_R_NOT_W: out std_ulogic;
        --! The CPU's SYNC, while it owns the address pins. Not a pin on the
        --! real chip.
        sync_SYNC: out std_ulogic;
        --! The `OUT0`-`OUT2` pins (see @ref io_ports)
        out_pins_OUT: out std_ulogic_vector(2 downto 0);
        --! The `/IN0` pin: low while reading `$4016`
        in0_pin_n_IN0: out std_ulogic;
        --! The `/IN1` pin: low while reading `$4017`
        in1_pin_n_IN1: out std_ulogic;
        --! Square 0's output (`SQA`, to the `AUX A` DAC)
        output_SQA: out std_ulogic_vector(3 downto 0);
        --! Square 1's output (`SQB`, to the `AUX A` DAC)
        output_SQB: out std_ulogic_vector(3 downto 0);
        --! The triangle's output (`TRI`, to the `AUX B` DAC)
        output_TRI: out std_ulogic_vector(3 downto 0);
        --! The noise channel's output (`RND`, to the `AUX B` DAC)
        output_RND: out std_ulogic_vector(3 downto 0);
        --! The DMC's output (`DMC`, to the `AUX B` DAC)
        output_DMC: out std_ulogic_vector(6 downto 0)
    );
end entity;

architecture rtl of ricoh_2a03 is
    -- #region Components
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
    component aclk_generator is
        port(
            phi1: in std_ulogic;
            phi2: in std_ulogic;
            reset_RES: in std_ulogic;
            aclk1: out std_ulogic;
            aclk2: out std_ulogic;
            metaclock: in std_ulogic
        );
    end component;
    component register_decoder is
        port(
            phi1: in std_ulogic;
            cpu_address: in std_ulogic_vector(15 downto 0);
            pin_address: in std_ulogic_vector(4 downto 0);
            read_not_write_R_NOT_W: in std_ulogic;
            debug_DBG: in std_ulogic;
            write_W4000: out std_ulogic;
            write_W4001: out std_ulogic;
            write_W4002: out std_ulogic;
            write_W4003: out std_ulogic;
            write_W4004: out std_ulogic;
            write_W4005: out std_ulogic;
            write_W4006: out std_ulogic;
            write_W4007: out std_ulogic;
            write_W4008: out std_ulogic;
            write_W400A: out std_ulogic;
            write_W400B: out std_ulogic;
            write_W400C: out std_ulogic;
            write_W400E: out std_ulogic;
            write_W400F: out std_ulogic;
            write_W4010: out std_ulogic;
            write_W4011: out std_ulogic;
            write_W4012: out std_ulogic;
            write_W4013: out std_ulogic;
            write_W4014: out std_ulogic;
            write_W4015: out std_ulogic;
            write_W4016: out std_ulogic;
            write_W4017: out std_ulogic;
            write_W401A: out std_ulogic;
            read_R4015: out std_ulogic;
            read_R4016: out std_ulogic;
            read_R4017: out std_ulogic;
            read_R4018: out std_ulogic;
            read_R4019: out std_ulogic;
            read_R401A: out std_ulogic;
            debug_read_DBGRD: out std_ulogic
        );
    end component;
    component frame_counter is
        port(
            phi1: in std_ulogic;
            aclk1: in std_ulogic;
            aclk2: in std_ulogic;
            reset_RES: in std_ulogic;
            bus_DB_in: in std_ulogic_vector(7 downto 0);
            write_W4017: in std_ulogic;
            read_R4015: in std_ulogic;
            dmc_interrupt_DMCINT: in std_ulogic;
            bus_DB_out: out std_ulogic_vector(7 downto 0);
            interrupt_INT: out std_ulogic;
            quarter_frame_LFO1: out std_ulogic;
            half_frame_LFO2: out std_ulogic;
            metaclock: in std_ulogic
        );
    end component;
    component length_decoder is
        port(
            bus_DB_in: in std_ulogic_vector(7 downto 0);
            length_value: out std_ulogic_vector(7 downto 0)
        );
    end component;
    component length_counter is
        generic(
            status_bit: natural range 0 to 7 := 0
        );
        port(
            aclk1: in std_ulogic;
            aclk2: in std_ulogic;
            reset_RES: in std_ulogic;
            bus_DB_in: in std_ulogic_vector(7 downto 0);
            write_length: in std_ulogic;
            write_W4015: in std_ulogic;
            read_R4015: in std_ulogic;
            length_value: in std_ulogic_vector(7 downto 0);
            half_frame_LFO2: in std_ulogic;
            length_carry_LC: in std_ulogic;
            silenced_NO: out std_ulogic;
            bus_DB_out: out std_ulogic_vector(7 downto 0);
            metaclock: in std_ulogic
        );
    end component;
    component square_channel is
        generic(
            negate_carry_DEC: boolean := false
        );
        port(
            aclk1: in std_ulogic;
            aclk2: in std_ulogic;
            reset_RES: in std_ulogic;
            bus_DB_in: in std_ulogic_vector(7 downto 0);
            write_control_WR0: in std_ulogic;
            write_sweep_WR1: in std_ulogic;
            write_period_low_WR2: in std_ulogic;
            write_period_high_WR3: in std_ulogic;
            quarter_frame_LFO1: in std_ulogic;
            half_frame_LFO2: in std_ulogic;
            silenced_NOSQ: in std_ulogic;
            debug_lock_LOCK: in std_ulogic;
            length_carry_LC: out std_ulogic;
            output_SQ: out std_ulogic_vector(3 downto 0);
            metaclock: in std_ulogic
        );
    end component;
    component triangle_channel is
        port(
            phi1: in std_ulogic;
            aclk1: in std_ulogic;
            reset_RES: in std_ulogic;
            bus_DB_in: in std_ulogic_vector(7 downto 0);
            write_W4008: in std_ulogic;
            write_W400A: in std_ulogic;
            write_W400B: in std_ulogic;
            write_W401A: in std_ulogic;
            quarter_frame_LFO1: in std_ulogic;
            silenced_NOTRI: in std_ulogic;
            debug_lock_LOCK: in std_ulogic;
            length_carry_LC: out std_ulogic;
            output_TRI: out std_ulogic_vector(3 downto 0);
            metaclock: in std_ulogic
        );
    end component;
    component noise_channel is
        port(
            aclk1: in std_ulogic;
            aclk2: in std_ulogic;
            reset_RES: in std_ulogic;
            bus_DB_in: in std_ulogic_vector(7 downto 0);
            write_W400C: in std_ulogic;
            write_W400E: in std_ulogic;
            write_W400F: in std_ulogic;
            quarter_frame_LFO1: in std_ulogic;
            silenced_NORND: in std_ulogic;
            debug_lock_LOCK: in std_ulogic;
            length_carry_LC: out std_ulogic;
            output_RND: out std_ulogic_vector(3 downto 0);
            metaclock: in std_ulogic
        );
    end component;
    component dpcm_channel is
        port(
            phi1: in std_ulogic;
            aclk1: in std_ulogic;
            aclk2: in std_ulogic;
            reset_RES: in std_ulogic;
            bus_DB_in: in std_ulogic_vector(7 downto 0);
            read_not_write_R_NOT_W: in std_ulogic;
            debug_lock_LOCK: in std_ulogic;
            write_W4010: in std_ulogic;
            write_W4011: in std_ulogic;
            write_W4012: in std_ulogic;
            write_W4013: in std_ulogic;
            write_W4015: in std_ulogic;
            read_R4015: in std_ulogic;
            dmc_address_bus_DMCAB: out std_ulogic;
            dmc_running_RUNDMC: out std_ulogic;
            dmc_ready_DMCRDY: out std_ulogic;
            dmc_interrupt_DMCINT: out std_ulogic;
            dmc_address: out std_ulogic_vector(15 downto 0);
            bus_DB_out: out std_ulogic_vector(7 downto 0);
            output_DMC: out std_ulogic_vector(6 downto 0);
            metaclock: in std_ulogic
        );
    end component;
    component sprite_dma is
        port(
            phi1: in std_ulogic;
            aclk1: in std_ulogic;
            aclk2: in std_ulogic;
            reset_RES: in std_ulogic;
            read_not_write_R_NOT_W: in std_ulogic;
            write_W4014: in std_ulogic;
            bus_DB_in: in std_ulogic_vector(7 downto 0);
            dmc_running_RUNDMC: in std_ulogic;
            dmc_ready_DMCRDY: in std_ulogic;
            sprite_address: out std_ulogic_vector(15 downto 0);
            read_memory_SPR_CPU: out std_ulogic;
            write_ppu_SPR_PPU: out std_ulogic;
            ready_RDY: out std_ulogic;
            metaclock: in std_ulogic
        );
    end component;
    component address_multiplexer is
        port(
            read_memory_SPR_CPU: in std_ulogic;
            write_ppu_SPR_PPU: in std_ulogic;
            dmc_address_bus_DMCAB: in std_ulogic;
            dmc_address: in std_ulogic_vector(15 downto 0);
            sprite_address: in std_ulogic_vector(15 downto 0);
            cpu_address: in std_ulogic_vector(15 downto 0);
            pin_address: out std_ulogic_vector(15 downto 0)
        );
    end component;
    component dma_buffer is
        port(
            phi2: in std_ulogic;
            write_ppu_SPR_PPU: in std_ulogic;
            read_not_write_R_NOT_W: in std_ulogic;
            read_R4015: in std_ulogic;
            debug_read_DBGRD: in std_ulogic;
            bus_DB_in: in std_ulogic_vector(7 downto 0);
            bus_DB_out: out std_ulogic_vector(7 downto 0);
            read_not_write_RW: out std_ulogic;
            pins_input_RD: out std_ulogic;
            pins_isolated_WR: out std_ulogic;
            metaclock: in std_ulogic
        );
    end component;
    component io_ports is
        port(
            aclk2: in std_ulogic;
            bus_DB_in: in std_ulogic_vector(7 downto 0);
            write_W4016: in std_ulogic;
            read_R4016: in std_ulogic;
            read_R4017: in std_ulogic;
            out_pins_OUT: out std_ulogic_vector(2 downto 0);
            in0_pin_n_IN0: out std_ulogic;
            in1_pin_n_IN1: out std_ulogic;
            metaclock: in std_ulogic
        );
    end component;
    component debug_registers is
        port(
            reset_RES: in std_ulogic;
            bus_DB_in: in std_ulogic_vector(7 downto 0);
            write_W401A: in std_ulogic;
            read_R4018: in std_ulogic;
            read_R4019: in std_ulogic;
            read_R401A: in std_ulogic;
            output_SQA: in std_ulogic_vector(3 downto 0);
            output_SQB: in std_ulogic_vector(3 downto 0);
            output_TRI: in std_ulogic_vector(3 downto 0);
            output_RND: in std_ulogic_vector(3 downto 0);
            output_DMC: in std_ulogic_vector(6 downto 0);
            bus_DB_out: out std_ulogic_vector(7 downto 0);
            debug_lock_LOCK: out std_ulogic;
            metaclock: in std_ulogic
        );
    end component;
    for cpu: mos_6502 use entity work.mos_6502;
    for aclk: aclk_generator use entity work.aclk_generator;
    for regs: register_decoder use entity work.register_decoder;
    for frame: frame_counter use entity work.frame_counter;
    for length_pla: length_decoder use entity work.length_decoder;
    for all: length_counter use entity work.length_counter;
    for all: square_channel use entity work.square_channel;
    for triangle: triangle_channel use entity work.triangle_channel;
    for noise: noise_channel use entity work.noise_channel;
    for delta_modulation: dpcm_channel use entity work.dpcm_channel;
    for spr_dma: sprite_dma use entity work.sprite_dma;
    for mux: address_multiplexer use entity work.address_multiplexer;
    for dma_buf: dma_buffer use entity work.dma_buffer;
    for io: io_ports use entity work.io_ports;
    for dbg: debug_registers use entity work.debug_registers;
    -- #endregion

    -- #region Clocks, reset and CPU
    --! @ref Ricoh_2A03_Signal_RES
    signal RES: std_ulogic;
    signal ACLK1: std_ulogic;
    signal ACLK2: std_ulogic;
    --! The CPU's address bus (`CPU_A`)
    signal cpu_address: std_ulogic_vector(15 downto 0);
    --! The address on the pins (`A`)
    signal pin_address: std_ulogic_vector(15 downto 0);
    --! The CPU's R/W
    signal cpu_R_NOT_W: std_ulogic;
    signal cpu_SYNC: std_ulogic;
    --! The CPU's `/IRQ`: the pin, or the APU's interrupt
    signal cpu_n_IRQ: std_ulogic;
    --! @ref Ricoh_2A03_Signal_RDY
    signal RDY: std_ulogic;
    -- #endregion

    -- #region Register strobes
    signal W4000, W4001, W4002, W4003, W4004, W4005, W4006, W4007: std_ulogic;
    signal W4008, W400A, W400B, W400C, W400E, W400F: std_ulogic;
    signal W4010, W4011, W4012, W4013, W4014, W4015, W4016, W4017: std_ulogic;
    signal W401A: std_ulogic;
    signal R4015, R4016, R4017, R4018, R4019, R401A: std_ulogic;
    --! @ref Ricoh_2A03_Signal_DBGRD
    signal DBGRD: std_ulogic;
    -- #endregion

    -- #region APU
    signal LFO1: std_ulogic;
    signal LFO2: std_ulogic;
    --! @ref Ricoh_2A03_Signal_INT
    signal INT: std_ulogic;
    signal LOCK: std_ulogic;
    signal length_value: std_ulogic_vector(7 downto 0);
    signal SQA_LC, SQB_LC, TRI_LC, RND_LC: std_ulogic;
    signal NOSQA, NOSQB, NOTRI, NORND: std_ulogic;
    signal SQA, SQB, TRI, RND: std_ulogic_vector(3 downto 0);
    signal DMC: std_ulogic_vector(6 downto 0);
    signal DMCAB, RUNDMC, DMCRDY, DMCINT: std_ulogic;
    signal dmc_address: std_ulogic_vector(15 downto 0);
    -- #endregion

    -- #region DMA and pins
    signal sprite_address: std_ulogic_vector(15 downto 0);
    signal SPR_CPU, SPR_PPU: std_ulogic;
    --! `RW`, for the R/W pin
    signal RW: std_ulogic;
    --! `RD`: the data pins are inputs
    signal RD: std_ulogic;
    --! `WR`: the data pins don't drive the internal data bus
    signal WR: std_ulogic;
    -- #endregion

    -- #region Data bus
    --! Each driver of @ref Ricoh_2A03_DB, all ones when released
    signal cpu_DB: std_ulogic_vector(7 downto 0);
    signal pins_DB: std_ulogic_vector(7 downto 0);
    signal dma_buffer_DB: std_ulogic_vector(7 downto 0);
    signal frame_DB: std_ulogic_vector(7 downto 0);
    signal square0_length_DB, square1_length_DB: std_ulogic_vector(7 downto 0);
    signal triangle_length_DB, noise_length_DB: std_ulogic_vector(7 downto 0);
    signal dmc_DB: std_ulogic_vector(7 downto 0);
    signal debug_DB: std_ulogic_vector(7 downto 0);
    --! The AND of every driver
    signal drivers_DB: std_ulogic_vector(7 downto 0);
    --! The bits a register read drives while the pins are cut off
    signal register_read_DB: std_ulogic_vector(7 downto 0);
    --! The bits nothing drives
    signal floating_DB: std_ulogic_vector(7 downto 0);
    --! The bus's last value, which the floating bits keep
    signal keeper_DB: std_ulogic_vector(7 downto 0) := (others => '1');
    --! @ref Ricoh_2A03_DB
    signal bus_DB: std_ulogic_vector(7 downto 0);
    -- #endregion
begin
    RES <= not reset_pin_n_RES;
    cpu_n_IRQ <= irq_pin_n_IRQ and not INT;

    --! The 6502 core, with its decimal mode cut out to match the 2A03
    cpu: mos_6502
        generic map(
            decimal_mode => false
        )
        port map(
            metaclock => metaclock,
            phi1 => phi1,
            phi2 => phi2,
            reset_pin_n_RES => reset_pin_n_RES,
            irq_pin_n_IRQ => cpu_n_IRQ,
            nmi_pin_n_NMI => nmi_pin_n_NMI,
            ready_pin_RDY => RDY,
            address => cpu_address,
            data_in => bus_DB,
            data_out => cpu_DB,
            read_not_write_R_NOT_W => cpu_R_NOT_W,
            sync_SYNC => cpu_SYNC
        );

    aclk: aclk_generator
        port map(
            phi1 => phi1,
            phi2 => phi2,
            reset_RES => RES,
            aclk1 => ACLK1,
            aclk2 => ACLK2,
            metaclock => metaclock
        );

    regs: register_decoder
        port map(
            phi1 => phi1,
            cpu_address => cpu_address,
            pin_address => pin_address(4 downto 0),
            read_not_write_R_NOT_W => cpu_R_NOT_W,
            debug_DBG => debug_pin_DBG,
            write_W4000 => W4000,
            write_W4001 => W4001,
            write_W4002 => W4002,
            write_W4003 => W4003,
            write_W4004 => W4004,
            write_W4005 => W4005,
            write_W4006 => W4006,
            write_W4007 => W4007,
            write_W4008 => W4008,
            write_W400A => W400A,
            write_W400B => W400B,
            write_W400C => W400C,
            write_W400E => W400E,
            write_W400F => W400F,
            write_W4010 => W4010,
            write_W4011 => W4011,
            write_W4012 => W4012,
            write_W4013 => W4013,
            write_W4014 => W4014,
            write_W4015 => W4015,
            write_W4016 => W4016,
            write_W4017 => W4017,
            write_W401A => W401A,
            read_R4015 => R4015,
            read_R4016 => R4016,
            read_R4017 => R4017,
            read_R4018 => R4018,
            read_R4019 => R4019,
            read_R401A => R401A,
            debug_read_DBGRD => DBGRD
        );

    -- #region APU
    frame: frame_counter
        port map(
            phi1 => phi1,
            aclk1 => ACLK1,
            aclk2 => ACLK2,
            reset_RES => RES,
            bus_DB_in => bus_DB,
            write_W4017 => W4017,
            read_R4015 => R4015,
            dmc_interrupt_DMCINT => DMCINT,
            bus_DB_out => frame_DB,
            interrupt_INT => INT,
            quarter_frame_LFO1 => LFO1,
            half_frame_LFO2 => LFO2,
            metaclock => metaclock
        );

    length_pla: length_decoder
        port map(
            bus_DB_in => bus_DB,
            length_value => length_value
        );

    square0_length: length_counter
        generic map(status_bit => 0)
        port map(
            aclk1 => ACLK1,
            aclk2 => ACLK2,
            reset_RES => RES,
            bus_DB_in => bus_DB,
            write_length => W4003,
            write_W4015 => W4015,
            read_R4015 => R4015,
            length_value => length_value,
            half_frame_LFO2 => LFO2,
            length_carry_LC => SQA_LC,
            silenced_NO => NOSQA,
            bus_DB_out => square0_length_DB,
            metaclock => metaclock
        );

    square1_length: length_counter
        generic map(status_bit => 1)
        port map(
            aclk1 => ACLK1,
            aclk2 => ACLK2,
            reset_RES => RES,
            bus_DB_in => bus_DB,
            write_length => W4007,
            write_W4015 => W4015,
            read_R4015 => R4015,
            length_value => length_value,
            half_frame_LFO2 => LFO2,
            length_carry_LC => SQB_LC,
            silenced_NO => NOSQB,
            bus_DB_out => square1_length_DB,
            metaclock => metaclock
        );

    triangle_length: length_counter
        generic map(status_bit => 2)
        port map(
            aclk1 => ACLK1,
            aclk2 => ACLK2,
            reset_RES => RES,
            bus_DB_in => bus_DB,
            write_length => W400B,
            write_W4015 => W4015,
            read_R4015 => R4015,
            length_value => length_value,
            half_frame_LFO2 => LFO2,
            length_carry_LC => TRI_LC,
            silenced_NO => NOTRI,
            bus_DB_out => triangle_length_DB,
            metaclock => metaclock
        );

    noise_length: length_counter
        generic map(status_bit => 3)
        port map(
            aclk1 => ACLK1,
            aclk2 => ACLK2,
            reset_RES => RES,
            bus_DB_in => bus_DB,
            write_length => W400F,
            write_W4015 => W4015,
            read_R4015 => R4015,
            length_value => length_value,
            half_frame_LFO2 => LFO2,
            length_carry_LC => RND_LC,
            silenced_NO => NORND,
            bus_DB_out => noise_length_DB,
            metaclock => metaclock
        );

    square0: square_channel
        generic map(negate_carry_DEC => false)
        port map(
            aclk1 => ACLK1,
            aclk2 => ACLK2,
            reset_RES => RES,
            bus_DB_in => bus_DB,
            write_control_WR0 => W4000,
            write_sweep_WR1 => W4001,
            write_period_low_WR2 => W4002,
            write_period_high_WR3 => W4003,
            quarter_frame_LFO1 => LFO1,
            half_frame_LFO2 => LFO2,
            silenced_NOSQ => NOSQA,
            debug_lock_LOCK => LOCK,
            length_carry_LC => SQA_LC,
            output_SQ => SQA,
            metaclock => metaclock
        );

    square1: square_channel
        generic map(negate_carry_DEC => true)
        port map(
            aclk1 => ACLK1,
            aclk2 => ACLK2,
            reset_RES => RES,
            bus_DB_in => bus_DB,
            write_control_WR0 => W4004,
            write_sweep_WR1 => W4005,
            write_period_low_WR2 => W4006,
            write_period_high_WR3 => W4007,
            quarter_frame_LFO1 => LFO1,
            half_frame_LFO2 => LFO2,
            silenced_NOSQ => NOSQB,
            debug_lock_LOCK => LOCK,
            length_carry_LC => SQB_LC,
            output_SQ => SQB,
            metaclock => metaclock
        );

    triangle: triangle_channel
        port map(
            phi1 => phi1,
            aclk1 => ACLK1,
            reset_RES => RES,
            bus_DB_in => bus_DB,
            write_W4008 => W4008,
            write_W400A => W400A,
            write_W400B => W400B,
            write_W401A => W401A,
            quarter_frame_LFO1 => LFO1,
            silenced_NOTRI => NOTRI,
            debug_lock_LOCK => LOCK,
            length_carry_LC => TRI_LC,
            output_TRI => TRI,
            metaclock => metaclock
        );

    noise: noise_channel
        port map(
            aclk1 => ACLK1,
            aclk2 => ACLK2,
            reset_RES => RES,
            bus_DB_in => bus_DB,
            write_W400C => W400C,
            write_W400E => W400E,
            write_W400F => W400F,
            quarter_frame_LFO1 => LFO1,
            silenced_NORND => NORND,
            debug_lock_LOCK => LOCK,
            length_carry_LC => RND_LC,
            output_RND => RND,
            metaclock => metaclock
        );

    delta_modulation: dpcm_channel
        port map(
            phi1 => phi1,
            aclk1 => ACLK1,
            aclk2 => ACLK2,
            reset_RES => RES,
            bus_DB_in => bus_DB,
            read_not_write_R_NOT_W => cpu_R_NOT_W,
            debug_lock_LOCK => LOCK,
            write_W4010 => W4010,
            write_W4011 => W4011,
            write_W4012 => W4012,
            write_W4013 => W4013,
            write_W4015 => W4015,
            read_R4015 => R4015,
            dmc_address_bus_DMCAB => DMCAB,
            dmc_running_RUNDMC => RUNDMC,
            dmc_ready_DMCRDY => DMCRDY,
            dmc_interrupt_DMCINT => DMCINT,
            dmc_address => dmc_address,
            bus_DB_out => dmc_DB,
            output_DMC => DMC,
            metaclock => metaclock
        );
    -- #endregion

    -- #region DMA, I/O and debug
    spr_dma: sprite_dma
        port map(
            phi1 => phi1,
            aclk1 => ACLK1,
            aclk2 => ACLK2,
            reset_RES => RES,
            read_not_write_R_NOT_W => cpu_R_NOT_W,
            write_W4014 => W4014,
            bus_DB_in => bus_DB,
            dmc_running_RUNDMC => RUNDMC,
            dmc_ready_DMCRDY => DMCRDY,
            sprite_address => sprite_address,
            read_memory_SPR_CPU => SPR_CPU,
            write_ppu_SPR_PPU => SPR_PPU,
            ready_RDY => RDY,
            metaclock => metaclock
        );

    mux: address_multiplexer
        port map(
            read_memory_SPR_CPU => SPR_CPU,
            write_ppu_SPR_PPU => SPR_PPU,
            dmc_address_bus_DMCAB => DMCAB,
            dmc_address => dmc_address,
            sprite_address => sprite_address,
            cpu_address => cpu_address,
            pin_address => pin_address
        );

    dma_buf: dma_buffer
        port map(
            phi2 => phi2,
            write_ppu_SPR_PPU => SPR_PPU,
            read_not_write_R_NOT_W => cpu_R_NOT_W,
            read_R4015 => R4015,
            debug_read_DBGRD => DBGRD,
            bus_DB_in => bus_DB,
            bus_DB_out => dma_buffer_DB,
            read_not_write_RW => RW,
            pins_input_RD => RD,
            pins_isolated_WR => WR,
            metaclock => metaclock
        );

    io: io_ports
        port map(
            aclk2 => ACLK2,
            bus_DB_in => bus_DB,
            write_W4016 => W4016,
            read_R4016 => R4016,
            read_R4017 => R4017,
            out_pins_OUT => out_pins_OUT,
            in0_pin_n_IN0 => in0_pin_n_IN0,
            in1_pin_n_IN1 => in1_pin_n_IN1,
            metaclock => metaclock
        );

    dbg: debug_registers
        port map(
            reset_RES => RES,
            bus_DB_in => bus_DB,
            write_W401A => W401A,
            read_R4018 => R4018,
            read_R4019 => R4019,
            read_R401A => R401A,
            output_SQA => SQA,
            output_SQB => SQB,
            output_TRI => TRI,
            output_RND => RND,
            output_DMC => DMC,
            bus_DB_out => debug_DB,
            debug_lock_LOCK => LOCK,
            metaclock => metaclock
        );
    -- #endregion

    -- #region Data bus
    pins_DB <= data_in when WR = '0' else (others => '1');
    drivers_DB <= cpu_DB and pins_DB and dma_buffer_DB and frame_DB
        and square0_length_DB and square1_length_DB and triangle_length_DB
        and noise_length_DB and dmc_DB and debug_DB;

    -- While the pins are cut off during a read, only the register being read
    -- drives the bus: $4015 drives every bit but 5, $4018 and $4019 every
    -- bit, and $401A bits 6-0. A debug read of any other register drives
    -- nothing.
    register_read_DB <= "11011111" when R4015 = '1'
        else "11111111" when R4018 = '1' or R4019 = '1'
        else "01111111" when R401A = '1'
        else "00000000";
    floating_DB <= not register_read_DB when WR = '1' and RD = '1'
        else "00000000";
    bus_DB <= drivers_DB and (keeper_DB or not floating_DB);

    process(metaclock)
    begin
        if rising_edge(metaclock) then
            keeper_DB <= bus_DB;
        end if;
    end process;
    -- #endregion

    -- #region Pins
    address <= pin_address;
    data_out <= bus_DB when RD = '0' else (others => '1');
    read_not_write_R_NOT_W <= RW;
    sync_SYNC <= cpu_SYNC and not (SPR_CPU or SPR_PPU or DMCAB);
    output_SQA <= SQA;
    output_SQB <= SQB;
    output_TRI <= TRI;
    output_RND <= RND;
    output_DMC <= DMC;
    -- #endregion
end architecture;
