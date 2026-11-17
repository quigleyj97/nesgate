library ieee;
use ieee.std_logic_1164.all;

--! @file
--! @brief Ready control logic for the Ricoh 2A03
--! @details Stalls the CPU while the external `RDY` pin is low, except during
--! write cycles, and works out which cycles write.
--!
--! The 6502 can only stall on read cycles. So the ready latch takes `RDY`, but
--! forces @ref Ricoh_2A03_Signal_ready high if the cycle is a write, which is
--! @ref Ricoh_2A03_Signal_WR latched during the previous Phi1:
--!
--! - The write latch (Phi2) is set when the next cycle writes to memory: a
--!   store (@ref Ricoh_2A03_Signal_STOR), a PC push
--!   (@ref Ricoh_2A03_Signal_PC_DB), BRK T4 or a push at T2 (decoder lines 98
--!   and 100), or a read-modify-write cycle (@ref Ricoh_2A03_Signal_T6 and
--!   @ref Ricoh_2A03_Signal_T7).
--! - `WR` is the write latch while the CPU is ready, except during reset
--!   (@ref Ricoh_2A03_Signal_DORES).
--! - The R/W pin latch (Phi1) holds `WR`, inverted, for the whole cycle, as
--!   @ref Ricoh_Signal_R_NOT_W.
--! - The ready latch (Phi2) is `RDY`, or `WR` from the last Phi1.
--!
--! It also makes two delayed copies of the ready state:
--!
--! - @ref Ricoh_2A03_Signal_ReadyPhi1 is `ready` latched during Phi1, and held
--!   through Phi2 while `ready` itself changes.
--! - @ref Ricoh_2A03_Signal_PRDY is the `RDY` pin latched during Phi2, then
--!   during Phi1.
--!
--! On the real chip this is part of the dispatcher, and outputs `/ready` and
--! `NotReadyPhi1` active-low. The `/PRDY` latches sit next to the `RDY` pad.
--! This core keeps every signal active-high, like the rest of its control
--! signals.
--!
--! Every latch is sampled on the @ref metaclock while its phase is high, like
--! the other registers in this core. Each signal below stores the active-high
--! value. They start out ready and not writing.

--! Ready control logic, making ready, WR, ReadyPhi1 and PRDY
entity ready_controller is
    port(
        --! @ref Ricoh_2A03_Phi1
        phi1: in std_ulogic;
        --! @ref Ricoh_2A03_Phi2
        phi2: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_RDY
        ready_pin_RDY: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_STOR
        store_cycle_STOR: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_PC_DB
        pc_to_db_PC_DB: in std_ulogic;
        --! Decoder line 98 (BRK T4), from @ref decoder_rom
        brk_t4_X98: in std_ulogic;
        --! Decoder line 100 (push T2), from @ref decoder_rom
        push_t2_X100: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_T6
        rmw_cycle_T6: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_T7
        rmw_cycle_T7: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_DORES
        resetting_DORES: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_ready
        ready: out std_ulogic;
        --! @ref Ricoh_2A03_Signal_WR
        write_cycle_WR: out std_ulogic;
        --! @ref Ricoh_Signal_R_NOT_W, the R/W pin
        read_not_write_R_NOT_W: out std_ulogic;
        --! @ref Ricoh_2A03_Signal_ReadyPhi1
        ready_phi1_ReadyPhi1: out std_ulogic;
        --! @ref Ricoh_2A03_Signal_PRDY
        previous_ready_PRDY: out std_ulogic;
        --! Clock to drive the latch circuitry
        --! @ref metaclock
        metaclock: in std_ulogic
    );
end entity ready_controller;

architecture rtl of ready_controller is
    --! `wr_latch` (Phi2): the next cycle writes to memory
    signal write_latch: std_ulogic := '0';
    --! `ready_latch2` (Phi1): `WR`, so the ready latch ignores `RDY` on writes
    signal write_phi1_latch: std_ulogic := '0';
    --! `ready_latch1` (Phi2): `RDY`, or a write cycle
    signal ready_latch: std_ulogic := '1';
    --! `rdydelay_latch1` (Phi1): `ready`
    signal ready_delay_latch1: std_ulogic := '1';
    --! `rdydelay_latch2` (Phi2): `ready` from Phi1, which is `ReadyPhi1`
    signal ready_delay_latch2: std_ulogic := '1';
    --! `prdy_latch1` (Phi2): the `RDY` pin
    signal prdy_latch1: std_ulogic := '1';
    --! `prdy_latch2` (Phi1): the `RDY` pin from Phi2, which is `PRDY`
    signal prdy_latch2: std_ulogic := '1';
    --! The R/W pin latch (Phi1): `WR`, inverted
    signal rw_latch: std_ulogic := '1';

    signal WR: std_ulogic;
begin
    WR <= ready_latch and write_latch and not resetting_DORES;

    process(metaclock)
    begin
        if rising_edge(metaclock) then
            if phi1 = '1' then
                write_phi1_latch <= WR;
                rw_latch <= not WR;
                ready_delay_latch1 <= ready_latch;
                prdy_latch2 <= prdy_latch1;
            end if;

            if phi2 = '1' then
                write_latch <= store_cycle_STOR or pc_to_db_PC_DB or brk_t4_X98
                    or push_t2_X100 or rmw_cycle_T6 or rmw_cycle_T7;
                ready_latch <= ready_pin_RDY or write_phi1_latch;
                ready_delay_latch2 <= ready_delay_latch1;
                prdy_latch1 <= ready_pin_RDY;
            end if;
        end if;
    end process;

    ready <= ready_latch;
    write_cycle_WR <= WR;
    read_not_write_R_NOT_W <= rw_latch;
    ready_phi1_ReadyPhi1 <= ready_delay_latch2;
    previous_ready_PRDY <= prdy_latch2;
end architecture rtl;
