library ieee;
use ieee.std_logic_1164.all;

--! @file
--! @brief The 2A03's test mode registers, `$4018`-`$401A`
--! @details These only decode while the DBG pin is high (see
--! @ref register_decoder). Retail consoles tie it low.
--!
--! | Register | Read                            | Write                     |
--! |----------|---------------------------------|---------------------------|
--! | `$4018`  | Square 1 (7-4), square 0 (3-0)  |                           |
--! | `$4019`  | Noise (7-4), triangle (3-0)     |                           |
--! | `$401A`  | DMC (6-0)                       | Bit 7: `LOCK`. Bits 4-0: the triangle's output counter. |
--!
--! The reads put the channels' outputs on the data bus, as they go to the
--! DAC. Writing bit 7 of `$401A` sets @ref Ricoh_2A03_Signal_LOCK, which
--! freezes the channels (see each channel for how), so their outputs can be
--! read back steadily. Reset clears it.
--!
--! The `LOCK` flip-flop is sampled on the @ref metaclock.
entity debug_registers is
    port(
        --! @ref Ricoh_2A03_Signal_RES
        reset_RES: in std_ulogic;
        --! The internal data bus (@ref Ricoh_2A03_DB)
        bus_DB_in: in std_ulogic_vector(7 downto 0);
        --! `W401A`, from the @ref register_decoder
        write_W401A: in std_ulogic;
        --! `R4018`, from the @ref register_decoder
        read_R4018: in std_ulogic;
        --! `R4019`, from the @ref register_decoder
        read_R4019: in std_ulogic;
        --! `R401A`, from the @ref register_decoder
        read_R401A: in std_ulogic;
        --! Square 0's output (`SQA`)
        output_SQA: in std_ulogic_vector(3 downto 0);
        --! Square 1's output (`SQB`)
        output_SQB: in std_ulogic_vector(3 downto 0);
        --! The triangle's output (`TRI`)
        output_TRI: in std_ulogic_vector(3 downto 0);
        --! The noise channel's output (`RND`)
        output_RND: in std_ulogic_vector(3 downto 0);
        --! The DMC's output (`DMC`)
        output_DMC: in std_ulogic_vector(6 downto 0);
        --! Drives @ref Ricoh_2A03_DB during a debug read, all ones (released)
        --! otherwise
        bus_DB_out: out std_ulogic_vector(7 downto 0);
        --! @ref Ricoh_2A03_Signal_LOCK
        debug_lock_LOCK: out std_ulogic;
        --! @ref metaclock
        metaclock: in std_ulogic
    );
end entity debug_registers;

architecture rtl of debug_registers is
    signal lock: std_ulogic := '0';
begin
    process(metaclock)
    begin
        if rising_edge(metaclock) then
            if reset_RES = '1' then
                lock <= '0';
            elsif write_W401A = '1' then
                lock <= bus_DB_in(7);
            end if;
        end if;
    end process;

    bus_DB_out <= output_SQB & output_SQA when read_R4018 = '1'
        else output_RND & output_TRI when read_R4019 = '1'
        else '1' & output_DMC when read_R401A = '1'
        else (others => '1');
    debug_lock_LOCK <= lock;
end architecture rtl;
