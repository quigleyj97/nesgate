library ieee;
use ieee.std_logic_1164.all;

--! @file
--! @brief The frame counter ("Soft CLK"), which clocks the envelopes, sweeps
--! and length counters, and raises the frame interrupt
--! @details The frame counter is a 15-bit LFSR that steps once per APU cycle.
--! A PLA watches it for five states, which come round every 3728 or 3729
--! steps, and pulses the low frequency outputs on them:
--!
--! | PLA row | Steps from the start | `LFO1` | `LFO2` | Notes                     |
--! |---------|----------------------|--------|--------|---------------------------|
--! | 0       | 3728                 | yes    |        |                           |
--! | 1       | 7456                 | yes    | yes    |                           |
--! | 2       | 11185                | yes    |        |                           |
--! | 3       | 14914                | yes    | yes    | 4-step mode only. Restart, and set the interrupt. |
--! | 4       | 18640                | yes    | yes    | 5-step mode only. Restart. |
--!
--! @ref Ricoh_2A03_Signal_LFO1 (the quarter frame) clocks the envelopes and
--! the triangle's linear counter, and @ref Ricoh_2A03_Signal_LFO2 (the half
--! frame) clocks the sweeps and the length counters. They're pulses during
--! ACLK2. A sixth row spots the all-zeros state, which the LFSR could never
--! leave, and shifts a one in.
--!
--! `$4017` sets the mode (bit 7: 0 for four steps, 1 for five) and the
--! interrupt inhibit (bit 6). Writing it:
--!
--! - Clears the Z flip-flop. At the next ACLK1 the Z1 latch picks that up,
--!   and at the ACLK2 after that the LFSR restarts (from all ones) and the
--!   flip-flop sets again. So the restart comes three or four CPU cycles after
--!   the write, depending on which half of the APU cycle the write lands in.
--! - In 5-step mode, pulses both outputs during that ACLK2 too (`Z2`), so the
--!   envelopes, sweeps and length counters are clocked straight away.
--!
--! The interrupt flip-flop is set at PLA row 3, in 4-step mode only. Setting
--! the inhibit bit clears it and holds it clear, and so does reading `$4015`
--! (during Phi2) or reset. `$4015` bit 6 reads it, as latched during the last
--! ACLK1. Its output is ORed with the DMC's interrupt
--! (@ref Ricoh_2A03_Signal_DMCINT) into @ref Ricoh_2A03_Signal_INT, which
--! goes on to the CPU's `/IRQ`.
--!
--! The mode is latched during ACLK1 before the PLA and the LFSR control see
--! it. The interrupt flip-flop and Z2's latch read the register directly.
--!
--! The real chip outputs `/LFO1` and `/LFO2`, and keeps the LFSR and PLA in
--! complementary form. This core keeps everything active-high.
--!
--! Every latch is sampled on the @ref metaclock while its enable is high.
entity frame_counter is
    port(
        --! @ref MOS_6502_Phi1
        phi1: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_ACLK1
        aclk1: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_ACLK2
        aclk2: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_RES
        reset_RES: in std_ulogic;
        --! The internal data bus (@ref Ricoh_2A03_DB)
        bus_DB_in: in std_ulogic_vector(7 downto 0);
        --! `W4017`, from the @ref register_decoder
        write_W4017: in std_ulogic;
        --! `R4015`, from the @ref register_decoder
        read_R4015: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_DMCINT
        dmc_interrupt_DMCINT: in std_ulogic;
        --! Drives @ref Ricoh_2A03_DB bit 6 while reading `$4015`, all ones
        --! (released) otherwise
        bus_DB_out: out std_ulogic_vector(7 downto 0);
        --! @ref Ricoh_2A03_Signal_INT
        interrupt_INT: out std_ulogic;
        --! @ref Ricoh_2A03_Signal_LFO1
        quarter_frame_LFO1: out std_ulogic;
        --! @ref Ricoh_2A03_Signal_LFO2
        half_frame_LFO2: out std_ulogic;
        --! @ref metaclock
        metaclock: in std_ulogic
    );
end entity frame_counter;

architecture rtl of frame_counter is
    --! The PLA rows, as the value of each LFSR bit (bit 14 first)
    constant ROW_0: std_ulogic_vector(14 downto 0) := "001000001100001";
    constant ROW_1: std_ulogic_vector(14 downto 0) := "011011000000011";
    constant ROW_2: std_ulogic_vector(14 downto 0) := "010110011010011";
    constant ROW_3: std_ulogic_vector(14 downto 0) := "000101000011111";
    constant ROW_4: std_ulogic_vector(14 downto 0) := "111000110000101";

    --! `$4017` bit 7: 5-step mode
    signal mode_register: std_ulogic := '0';
    --! `$4017` bit 6: interrupt inhibit
    signal inhibit_register: std_ulogic := '0';
    --! The mode, latched during ACLK1
    signal mode_latch: std_ulogic := '0';
    --! The interrupt flip-flop
    signal interrupt_flag: std_ulogic := '0';
    --! The interrupt flip-flop, latched during ACLK1 for `$4015`
    signal interrupt_latch: std_ulogic := '0';

    --! The Z flip-flop: clear from a write to `$4017` until the LFSR restarts
    signal z_flag: std_ulogic := '0';
    --! The Z flip-flop, latched during ACLK1 (`Z1` is its inverse)
    signal z1_latch: std_ulogic := '0';
    --! The mode register, latched during ACLK1, for `Z2`
    signal z2_mode_latch: std_ulogic := '0';
    --! `Z2`: pulse the outputs straight after a write that selects 5-step mode
    signal Z2: std_ulogic;

    --! The LFSR's input nodes, loaded during ACLK2
    signal lfsr_nodes: std_ulogic_vector(14 downto 0) := (others => '1');
    --! The LFSR's output latches, loaded from the nodes during ACLK1
    signal lfsr: std_ulogic_vector(14 downto 0) := (others => '1');
    --! The value shifted into bit 0
    signal shift_in: std_ulogic;

    --! The PLA outputs
    signal pla: std_ulogic_vector(5 downto 0);
    --! `F1`: restart the LFSR (from all ones)
    signal restart_F1: std_ulogic;
    --! `F2`: step the LFSR
    signal step_F2: std_ulogic;
    --! Neither restarting nor waiting on a write
    signal counting: std_ulogic;

    function to_std(value: boolean) return std_ulogic is
    begin
        if value then
            return '1';
        end if;
        return '0';
    end function;
begin
    pla(0) <= to_std(lfsr = ROW_0);
    pla(1) <= to_std(lfsr = ROW_1);
    pla(2) <= to_std(lfsr = ROW_2);
    pla(3) <= to_std(lfsr = ROW_3 and mode_latch = '0');
    pla(4) <= to_std(lfsr = ROW_4);
    pla(5) <= to_std(lfsr = (lfsr'range => '0'));

    Z2 <= not z1_latch and z2_mode_latch;
    counting <= not (pla(3) or pla(4) or not z1_latch);
    restart_F1 <= aclk2 and not counting;
    step_F2 <= aclk2 and counting;
    shift_in <= (lfsr(13) xor lfsr(14)) or pla(5);

    process(metaclock)
    begin
        if rising_edge(metaclock) then
            if write_W4017 = '1' then
                mode_register <= bus_DB_in(7);
                inhibit_register <= bus_DB_in(6);
            end if;

            if reset_RES = '1' or (read_R4015 = '1' and phi1 = '0')
                or inhibit_register = '1' then
                interrupt_flag <= '0';
            elsif mode_register = '0' and pla(3) = '1' then
                interrupt_flag <= '1';
            end if;

            if reset_RES = '1' or write_W4017 = '1' then
                z_flag <= '0';
            elsif aclk2 = '1' and z1_latch = '0' then
                z_flag <= '1';
            end if;

            if step_F2 = '1' then
                lfsr_nodes <= lfsr(13 downto 0) & shift_in;
            elsif restart_F1 = '1' then
                lfsr_nodes <= (others => '1');
            end if;

            if aclk1 = '1' then
                mode_latch <= mode_register;
                interrupt_latch <= interrupt_flag;
                z1_latch <= z_flag;
                z2_mode_latch <= mode_register;
                lfsr <= lfsr_nodes;
            end if;
        end if;
    end process;

    quarter_frame_LFO1 <= aclk2 and (pla(0) or pla(1) or pla(2) or pla(3)
        or pla(4) or Z2);
    half_frame_LFO2 <= aclk2 and (pla(1) or pla(3) or pla(4) or Z2);

    interrupt_INT <= interrupt_flag or dmc_interrupt_DMCINT;
    bus_DB_out <= (6 => interrupt_latch, others => '1') when read_R4015 = '1'
        else (others => '1');
end architecture rtl;
