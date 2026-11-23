library ieee;
use ieee.std_logic_1164.all;

--! @file
--! @brief Interrupt and reset control logic for the MOS 6502
--! @details Detects interrupts and resets, and steers the BRK sequence that
--! handles them.
--!
--! The 6502 handles BRK, IRQ, NMI and reset with the same 7-cycle BRK
--! sequence. A hardware interrupt clears @ref MOS_6502_Signal_B_OUT, which
--! injects BRK into the next opcode fetch (@ref MOS_6502_Signal_0_IR) and
--! pushes P with B clear. This entity is made of these circuits:
--!
--! - The pad latches. `/NMI` is latched during Phi2, as `NMIP`. `/IRQ` and
--!   `/RES` are latched during Phi2 and then Phi1, as `IRQP` and
--!   @ref MOS_6502_Signal_RESP.
--! - The BRK cycle 6-7 counter. Decoder line 22 (BRK T5), while
--!   @ref MOS_6502_Signal_ready, starts cycle 6, which holds while the CPU
--!   isn't ready. @ref MOS_6502_Signal_BRK6E is cycle 6 latched during Phi2,
--!   so it lasts from Phi2 of cycle 6 through Phi1 of cycle 7, while ready.
--!   The two vector cycles (T5 while ready, then cycle 6) are the chip's `BRK7`
--!   signal, inverted.
--! - The reset flip-flop. `RESP` sets @ref MOS_6502_Signal_DORES, which
--!   holds until `BRK6E`.
--! - The NMI edge detector. Two flip-flops: "`/NMI` was high" is set while
--!   `/NMI` is high, and cleared once an edge has been detected. `DONMI` (do
--!   NMI) is set when `/NMI` is low and was high, outside the vector cycles,
--!   and holds until `BRK6E`. So an NMI that falls during the vector fetch is
--!   taken after it.
--! - The interrupt check and B flag. During T0, or T2 of a branch (decoder line
--!   80, `BR2`), a pending `DONMI`, or `IRQP` while the I flag is clear,
--!   clears `B_OUT`. It stays clear until `BRK6E`. Reset also clears it.
--! - The interrupt vector. During the vector cycles, latched during Phi2, these
--!   pull the low bits of ADL low, so the precharged bus reads the vector:
--!   @ref MOS_6502_Signal_0_ADL0 during T5, and
--!   @ref MOS_6502_Signal_0_ADL1 (reset) or @ref MOS_6502_Signal_0_ADL2
--!   (NMI) during both. That gives `0xFFFE` (IRQ/BRK), `0xFFFA` (NMI) and
--!   `0xFFFC` (reset).
--!
--! The real chip uses active-low `/NMIP`, `/IRQP`, `/DONMI`, `/ready` and 
--! `/I_OUT`, and drives the vector lines from inverted latch outputs. This core
--! keeps every signal active-high, like the rest of its control signals. The pins
--! themselves are active-low.
--!
--! Every latch is sampled on the @ref metaclock while its phase is high, like
--! the other registers in this core. Each signal below stores the active-high
--! value. Where a latch feeds another latch of the same phase through logic
--! (`nmip_latch` into `donmi_latch`), the second one settles a metaclock later,
--! as it would on the real chip while both latches are open. The chip's
--! `delay_latch1` and `ff1_latch` both latch `/DONMI` during Phi2, so this core
--! keeps only one of them. Everything starts out idle: no interrupt or reset
--! pending, outside the BRK sequence.

--! Interrupt and reset control, making BRK6E, DORES, B_OUT and the vector
entity interrupt_controller is
    port(
        --! @ref MOS_6502_Phi1
        phi1: in std_ulogic;
        --! @ref MOS_6502_Phi2
        phi2: in std_ulogic;
        --! @ref MOS_6502_Signal_NMI (active-low pin)
        nmi_pin_n_NMI: in std_ulogic;
        --! @ref MOS_6502_Signal_IRQ (active-low pin)
        irq_pin_n_IRQ: in std_ulogic;
        --! @ref MOS_6502_Signal_RES (active-low pin)
        reset_pin_n_RES: in std_ulogic;
        --! @ref MOS_6502_Signal_ready
        ready: in std_ulogic;
        --! Decoder line 22 (BRK T5), from @ref decoder_rom
        brk_t5_X22: in std_ulogic;
        --! Decoder line 80 (Branch T2, `BR2`), from @ref decoder_rom
        branch_t2_X80: in std_ulogic;
        --! @ref MOS_6502_Signal_T0
        cycle_T0: in std_ulogic;
        --! @ref MOS_6502_Signal_I_OUT
        interrupt_disable_I_OUT: in std_ulogic;
        --! @ref MOS_6502_Signal_RESP
        reset_pending_RESP: out std_ulogic;
        --! @ref MOS_6502_Signal_DORES
        resetting_DORES: out std_ulogic;
        --! @ref MOS_6502_Signal_BRK6E
        brk_cycle_6_end_BRK6E: out std_ulogic;
        --! @ref MOS_6502_Signal_B_OUT
        break_flag_B_OUT: out std_ulogic;
        --! @ref MOS_6502_Signal_0_ADL0
        clear_0_ADL0: out std_ulogic;
        --! @ref MOS_6502_Signal_0_ADL1
        clear_0_ADL1: out std_ulogic;
        --! @ref MOS_6502_Signal_0_ADL2
        clear_0_ADL2: out std_ulogic;
        --! Clock to drive the latch circuitry
        --! @ref metaclock
        metaclock: in std_ulogic
    );
end entity interrupt_controller;

architecture rtl of interrupt_controller is
    -- Pad latches

    --! `nmip_ff` (Phi2): the `/NMI` pin is low, which is `NMIP`
    signal nmi_pad_latch: std_ulogic := '0';
    --! `irqp_ff` (Phi2): the `/IRQ` pin is low
    signal irq_pad_latch1: std_ulogic := '0';
    --! `irqp_latch` (Phi1): the `/IRQ` pin from Phi2, which is `IRQP`
    signal irq_pad_latch2: std_ulogic := '0';
    --! `resp_ff` (Phi2): the `/RES` pin is low
    signal res_pad_latch1: std_ulogic := '0';
    --! `resp_latch` (Phi1): the `/RES` pin from Phi2, which is `RESP`
    signal res_pad_latch2: std_ulogic := '0';

    -- BRK cycles 6-7

    --! `brk5_latch` (Phi2): BRK T5 while ready
    signal brk5_latch: std_ulogic := '0';
    --! `brk6_latch1` (Phi1): BRK cycle 6
    signal brk6_latch1: std_ulogic := '0';
    --! `brk6_latch2` (Phi2): BRK cycle 6 from Phi1
    signal brk6_latch2: std_ulogic := '0';

    -- Reset flip-flop

    --! `res_latch1` (Phi2): `RESP`
    signal res_latch1: std_ulogic := '0';
    --! `res_latch2` (Phi1): `DORES`, until `BRK6E`
    signal res_latch2: std_ulogic := '0';

    -- NMI edge detector

    --! `nmip_latch` (Phi1): `NMIP`
    signal nmip_latch: std_ulogic := '0';
    --! `ff2_latch` (Phi2): `/NMI` was high
    signal nmi_was_high_latch: std_ulogic := '1';
    --! `brk7_latch` (Phi2): a vector cycle (the chip's `BRK7`, inverted)
    signal vector_cycle_latch: std_ulogic := '0';
    --! `donmi_latch` (Phi1): a falling edge of `/NMI`
    signal nmi_edge_latch: std_ulogic := '0';
    --! `ff1_latch` and `delay_latch1` (Phi2): `DONMI`
    signal donmi_latch: std_ulogic := '0';
    --! `delay_latch2` (Phi1): `DONMI` from Phi2, so the edge was detected
    signal donmi_delay_latch: std_ulogic := '0';
    --! `brk6e_latch` (Phi1): `BRK6E`
    signal brk6e_latch: std_ulogic := '0';

    -- B flag

    --! `b_latch1` (Phi2): no interrupt was found, or `BRK6E` ended one
    signal b_latch1: std_ulogic := '1';
    --! `b_latch2` (Phi1): an interrupt sequence is running
    signal b_latch2: std_ulogic := '0';

    -- Vector latches (Phi2)

    --! `zadl0_latch` (Phi2): `0/ADL0`
    signal zadl0_latch: std_ulogic := '0';
    --! `zadl1_latch` (Phi2): `0/ADL1`
    signal zadl1_latch: std_ulogic := '0';
    --! `zadl2_latch` (Phi2): `0/ADL2`
    signal zadl2_latch: std_ulogic := '0';

    signal NMIP: std_ulogic;
    signal IRQP: std_ulogic;
    signal RESP: std_ulogic;
    signal BRK5_RDY: std_ulogic;
    signal BRK6E: std_ulogic;
    --! T5 while ready, or cycle 6: when the vector is fetched
    signal vector_cycle: std_ulogic;
    signal DORES: std_ulogic;
    signal nmi_was_high: std_ulogic;
    signal DONMI: std_ulogic;
    --! An interrupt is pending at T0 or BR2
    signal interrupt: std_ulogic;
    --! The B flag flip-flop's set side: an interrupt sequence is running
    signal interrupt_sequence: std_ulogic;
begin
    NMIP <= nmi_pad_latch;
    IRQP <= irq_pad_latch2;
    RESP <= res_pad_latch2;

    BRK5_RDY <= brk_t5_X22 and ready;
    BRK6E <= brk6_latch2 and ready;
    vector_cycle <= BRK5_RDY or brk6_latch1;

    DORES <= res_latch1 or res_latch2;

    -- Set while /NMI is high, cleared once DONMI has gone through the delay
    nmi_was_high <= not nmip_latch or (nmi_was_high_latch and not donmi_delay_latch);
    -- Holds through donmi_latch until BRK6E (from Phi1) clears it
    DONMI <= nmi_edge_latch or (donmi_latch and not brk6e_latch);

    interrupt <= (branch_t2_X80 or cycle_T0)
        and ((IRQP and not interrupt_disable_I_OUT) or DONMI);
    interrupt_sequence <= not b_latch1 and not BRK6E;

    process(metaclock)
    begin
        if rising_edge(metaclock) then
            if phi1 = '1' then
                irq_pad_latch2 <= irq_pad_latch1;
                res_pad_latch2 <= res_pad_latch1;

                brk6_latch1 <= brk5_latch or (not ready and brk6_latch1);

                res_latch2 <= DORES and not BRK6E;

                nmip_latch <= NMIP;
                nmi_edge_latch <= not vector_cycle_latch and NMIP and nmi_was_high;
                donmi_delay_latch <= donmi_latch;
                brk6e_latch <= BRK6E;

                b_latch2 <= interrupt_sequence;
            end if;

            if phi2 = '1' then
                nmi_pad_latch <= not nmi_pin_n_NMI;
                irq_pad_latch1 <= not irq_pin_n_IRQ;
                res_pad_latch1 <= not reset_pin_n_RES;

                brk5_latch <= BRK5_RDY;
                brk6_latch2 <= brk6_latch1;

                res_latch1 <= RESP;

                nmi_was_high_latch <= nmi_was_high;
                vector_cycle_latch <= vector_cycle;
                donmi_latch <= DONMI;

                b_latch1 <= not interrupt and not b_latch2;

                zadl0_latch <= BRK5_RDY;
                zadl1_latch <= vector_cycle and DORES;
                zadl2_latch <= vector_cycle and not DORES and DONMI;
            end if;
        end if;
    end process;

    reset_pending_RESP <= RESP;
    resetting_DORES <= DORES;
    brk_cycle_6_end_BRK6E <= BRK6E;
    break_flag_B_OUT <= not DORES and not interrupt_sequence;
    clear_0_ADL0 <= zadl0_latch;
    clear_0_ADL1 <= zadl1_latch;
    clear_0_ADL2 <= zadl2_latch;
end architecture rtl;
