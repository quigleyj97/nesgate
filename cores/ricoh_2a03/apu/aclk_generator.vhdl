library ieee;
use ieee.std_logic_1164.all;

--! @file
--! @brief The APU clock generator, which makes ACLK1 and ACLK2 from Phi1 and
--! Phi2
--! @details The APU runs at half the CPU's rate. An APU cycle is two CPU
--! cycles, and its two phases are pulses during Phi1: ACLK1 during the Phi1 of
--! one CPU cycle, and ACLK2 during the Phi1 of the next. Both are low during
--! Phi2, when the CPU writes the APU's registers. See @ref Ricoh_2A03_clocks.
--!
--! Two latches make a divide-by-two counter. The Phi1 latch takes the Phi2
--! latch's value, and the Phi2 latch takes the Phi1 latch's value inverted, so
--! the Phi2 latch toggles every CPU cycle. During Phi1, ACLK1 is high if it's
--! set, and ACLK2 is high if it's clear.
--!
--! During reset (@ref Ricoh_2A03_Signal_RES) the Phi1 latch is held clear, so
--! the Phi2 latch is set from the second cycle on. ACLK1 is then high in every
--! Phi1, and so is ACLK2, so the counters the APU resets during reset see both
--! phases every cycle. Once reset ends, ACLK1 comes first.
--!
--! The chip outputs ACLK2 inverted, as `/ACLK2`, and parts of the APU invert it
--! back locally (the "other ACLK2s"). This core keeps it active-high.
--!
--! Both latches are sampled on the @ref metaclock while their phase is high.
entity aclk_generator is
    port(
        --! @ref MOS_6502_Phi1
        phi1: in std_ulogic;
        --! @ref MOS_6502_Phi2
        phi2: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_RES
        reset_RES: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_ACLK1
        aclk1: out std_ulogic;
        --! @ref Ricoh_2A03_Signal_ACLK2
        aclk2: out std_ulogic;
        --! @ref metaclock
        metaclock: in std_ulogic
    );
end entity aclk_generator;

architecture rtl of aclk_generator is
    --! The Phi1 latch's input: the Phi2 latch, unless resetting
    signal phi1_latch_in: std_ulogic;
    --! The Phi1 latch
    signal phi1_latch: std_ulogic := '0';
    --! The Phi2 latch: the Phi1 latch, inverted. ACLK1 comes next while it's
    --! set, ACLK2 while it's clear.
    signal phi2_latch: std_ulogic := '0';
begin
    phi1_latch_in <= phi2_latch and not reset_RES;

    process(metaclock)
    begin
        if rising_edge(metaclock) then
            if phi1 = '1' then
                phi1_latch <= phi1_latch_in;
            end if;
            if phi2 = '1' then
                phi2_latch <= not phi1_latch;
            end if;
        end if;
    end process;

    aclk1 <= phi1 and phi2_latch;
    aclk2 <= phi1 and not phi1_latch_in;
end architecture rtl;
