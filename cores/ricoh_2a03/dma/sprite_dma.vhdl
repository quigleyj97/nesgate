library ieee;
use ieee.std_logic_1164.all;

--! @file
--! @brief The sprite DMA controller, which copies a page of memory to the
--! PPU's `$2004`, and stalls the CPU while it does
--! @details Writing `$4014` stores the page in the high address register,
--! clears the 8-bit low address counter, and sets the start flip-flop, which
--! drops @ref Ricoh_2A03_Signal_RDY straight away. The 6502 ignores `RDY`
--! during writes, so the CPU only stalls at its next read.
--!
--! The DMA itself only starts during Phi2 of a CPU read cycle (`DOSPR`), once
--! the start flip-flop has been latched during an ACLK2. That sets the
--! running flip-flop, and from the next ACLK1 (`NOSPR` clear) the DMA owns
--! the address pins, and the start flip-flop clears. Then each APU cycle:
--!
--! 1. The ACLK1 half reads the next byte from memory (`SPR/CPU`), and the
--!    @ref dma_buffer latches it.
--! 2. The ACLK2 half writes it to `$2004` (`SPR/PPU`). ACLK2 also steps the
--!    low address counter (`SPRS`).
--!
--! The step after the counter's carry out (`SPRE`, latched during ACLK1),
--! which is the one after the read of `$xxFF`, clears the running flip-flop,
--! and the next ACLK1 hands the pins back to the CPU. So the DMA takes 256
--! APU cycles, plus one or two CPU cycles to start, depending on which half of
--! an APU cycle the CPU reaches its read in.
--!
--! While the DMC is fetching a sample (@ref Ricoh_2A03_Signal_RUNDMC), the
--! sprite DMA neither reads, writes nor steps, so it picks up where it left
--! off. `RDY` also stays low while the DMC isn't ready
--! (@ref Ricoh_2A03_Signal_DMCRDY), so this is where both DMAs stall the CPU.
--!
--! The `SPR/PPU` and `SPR/CPU` toggle is a flip-flop set by ACLK2 and cleared
--! by ACLK1. Every latch is sampled on the @ref metaclock while its enable is
--! high.
entity sprite_dma is
    port(
        --! @ref MOS_6502_Phi1. The DMA only starts while it's low.
        phi1: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_ACLK1
        aclk1: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_ACLK2
        aclk2: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_RES
        reset_RES: in std_ulogic;
        --! The CPU's @ref MOS_6502_Signal_R_NOT_W, to find its read cycles
        read_not_write_R_NOT_W: in std_ulogic;
        --! `W4014`, from the @ref register_decoder
        write_W4014: in std_ulogic;
        --! The internal data bus (@ref Ricoh_2A03_DB)
        bus_DB_in: in std_ulogic_vector(7 downto 0);
        --! @ref Ricoh_2A03_Signal_RUNDMC
        dmc_running_RUNDMC: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_DMCRDY
        dmc_ready_DMCRDY: in std_ulogic;
        --! The address of the next byte to read (`SPR_A`)
        sprite_address: out std_ulogic_vector(15 downto 0);
        --! @ref Ricoh_2A03_Signal_SPR_CPU
        read_memory_SPR_CPU: out std_ulogic;
        --! @ref Ricoh_2A03_Signal_SPR_PPU
        write_ppu_SPR_PPU: out std_ulogic;
        --! @ref Ricoh_2A03_Signal_RDY, to the CPU's `RDY`
        ready_RDY: out std_ulogic;
        --! @ref metaclock
        metaclock: in std_ulogic
    );
end entity sprite_dma;

architecture rtl of sprite_dma is
    component apu_counter is
        generic(
            width: positive := 8
        );
        port(
            clock: in std_ulogic;
            load: in std_ulogic;
            clear: in std_ulogic;
            step: in std_ulogic;
            carry_in: in std_ulogic;
            count_down: in std_ulogic;
            value_in: in std_ulogic_vector(width - 1 downto 0);
            value_out: out std_ulogic_vector(width - 1 downto 0);
            carry_out: out std_ulogic;
            metaclock: in std_ulogic
        );
    end component;
    for low_counter: apu_counter use entity work.apu_counter;

    --! The high address register: the page written to `$4014`
    signal page: std_ulogic_vector(7 downto 0) := (others => '0');
    --! The start flip-flop: `$4014` was written, and the DMA hasn't started
    signal start_pending: std_ulogic := '0';
    --! `start_pending`, latched during ACLK2
    signal start_latch: std_ulogic := '0';
    --! `DOSPR`: start the DMA
    signal DOSPR: std_ulogic;
    --! The running flip-flop
    signal running: std_ulogic := '0';
    --! `running`, latched during ACLK1 (`NOSPR` is its inverse)
    signal running_latch: std_ulogic := '0';
    --! The low address counter's carry out (`SPRE`), latched during ACLK1
    signal end_latch: std_ulogic := '0';
    signal SPRE: std_ulogic;
    --! `SPRS`: step the low address counter
    signal SPRS: std_ulogic;
    --! The direction toggle: set during the ACLK2 half (write), clear during
    --! the ACLK1 half (read)
    signal toggle: std_ulogic := '0';
    --! The DMA owns the address pins
    signal active: std_ulogic;
    signal low_address: std_ulogic_vector(7 downto 0);
begin
    low_counter: apu_counter
        generic map(width => 8)
        port map(
            clock => aclk1,
            load => write_W4014,
            clear => reset_RES,
            step => SPRS,
            carry_in => '1',
            count_down => '0',
            value_in => x"00",
            value_out => low_address,
            carry_out => SPRE,
            metaclock => metaclock
        );

    active <= running_latch and not dmc_running_RUNDMC;
    SPRS <= aclk2 and active;
    DOSPR <= start_latch and not phi1 and read_not_write_R_NOT_W;

    process(metaclock)
    begin
        if rising_edge(metaclock) then
            if write_W4014 = '1' then
                page <= bus_DB_in;
            end if;

            if running_latch = '1' or reset_RES = '1' then
                start_pending <= '0';
            elsif write_W4014 = '1' then
                start_pending <= '1';
            end if;

            if (SPRS = '1' and end_latch = '1') or reset_RES = '1' then
                running <= '0';
            elsif DOSPR = '1' then
                running <= '1';
            end if;

            if aclk1 = '1' then
                toggle <= '0';
            elsif aclk2 = '1' then
                toggle <= '1';
            end if;

            if aclk1 = '1' then
                end_latch <= SPRE;
                running_latch <= running;
            end if;
            if aclk2 = '1' then
                start_latch <= start_pending;
            end if;
        end if;
    end process;

    sprite_address <= page & low_address;
    read_memory_SPR_CPU <= active and not toggle;
    write_ppu_SPR_PPU <= active and toggle;
    ready_RDY <= not running_latch and not start_pending and dmc_ready_DMCRDY;
end architecture rtl;
