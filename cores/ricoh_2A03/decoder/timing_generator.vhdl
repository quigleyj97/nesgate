library ieee;
use ieee.std_logic_1164.all;

--! @file
--! @brief Timing generation logic for the Ricoh 2A03
--! @details Generates the cycle signals that tell the decoder ROM and the
--! random logic which cycle of an instruction the CPU is on, following the
--! "Timing Generation Logic" block of Donald F. Hanson's 6502 block diagram.
--!
--! On the real chip this logic is spread across the dispatcher, in between the
--! rest of the random logic. It is three separate counters:
--!
--! - The short cycle counter makes @ref Ricoh_2A03_Signal_T0 and
--!   @ref Ricoh_2A03_Signal_T1X. `T0` is set when the previous instruction is
--!   finishing (@ref Ricoh_2A03_Signal_TRESX), or when the next one only takes
--!   2 cycles (@ref Ricoh_2A03_Signal_TWOCYCLE), except during `T1`. It stays
--!   set until `T1X` follows it one cycle later.
--!   @ref Ricoh_2A03_Signal_T1 is @ref Ricoh_2A03_Signal_TRES1, latched during
--!   Phi1.
--! - The extended cycle counter is a shift register that moves `T1` through
--!   @ref Ricoh_2A03_Signal_T2 to @ref Ricoh_2A03_Signal_T5, one stage per
--!   cycle. `TRES2`, which is `TRESX` latched during Phi1, clears it.
--! - The very long cycle counter makes the read-modify-write cycles
--!   @ref Ricoh_2A03_Signal_T6 and @ref Ricoh_2A03_Signal_T7. `T6` follows a
--!   cycle with both @ref Ricoh_2A03_Signal_SHIFT and
--!   @ref Ricoh_2A03_Signal_MemOP set, and `T7` follows `T6`.
--!
--! While @ref Ricoh_2A03_Signal_ready is low, the T0/T1X, T2-T5 and T6 stages
--! hold their state, and `T7` doesn't start. `T1` and `TRES2` depend only on
--! their inputs, so the dispatch logic stalls those.
--!
--! The signals that control the counters (`TRES1`, `TRESX`, `/ready`) come from
--! the dispatch logic and aren't generated here.
--!
--! The real chip outputs `/T0`, `/T1X` and `/T2`-`/T5` active-low. This core
--! keeps all of them active-high, like the rest of its control signals. It also
--! leaves out two latches that are copies of others: the short cycle counter's
--! own latches of `TRES1` and `/TRESX` (`comp_latch1` and `comp_latch3`) hold
--! the same values, on the same phase, as `T1` and `TRES2`.
--!
--! Every latch is sampled on the @ref metaclock while its phase is high, like
--! the other registers in this core. Each signal below stores the active-high value.

--! Timing generation logic, generating the T0-T7 cycle signals
entity timing_generator is
    port(
        --! @ref Ricoh_2A03_Phi1
        phi1: in std_ulogic;
        --! @ref Ricoh_2A03_Phi2
        phi2: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_ready
        ready: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_TRES1
        reset_short_counter_TRES1: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_TRESX
        reset_counters_TRESX: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_TWOCYCLE, from @ref predecode_logic
        short_instruction_TWOCYCLE: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_SHIFT
        shift_instruction_SHIFT: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_MemOP
        memory_operation_MemOP: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_T0
        cycle_T0: out std_ulogic;
        --! @ref Ricoh_2A03_Signal_T1
        cycle_T1: out std_ulogic;
        --! @ref Ricoh_2A03_Signal_T1X
        cycle_T1X: out std_ulogic;
        --! @ref Ricoh_2A03_Signal_T2
        cycle_T2: out std_ulogic;
        --! @ref Ricoh_2A03_Signal_T3
        cycle_T3: out std_ulogic;
        --! @ref Ricoh_2A03_Signal_T4
        cycle_T4: out std_ulogic;
        --! @ref Ricoh_2A03_Signal_T5
        cycle_T5: out std_ulogic;
        --! @ref Ricoh_2A03_Signal_T6
        rmw_cycle_T6: out std_ulogic;
        --! @ref Ricoh_2A03_Signal_T7
        rmw_cycle_T7: out std_ulogic;
        --! Clock to drive the latch circuitry
        --! @ref metaclock
        metaclock: in std_ulogic
    );
end entity timing_generator;

architecture rtl of timing_generator is
    -- Short cycle counter, and T1

    --! `t1_latch` (Phi1): `TRES1`, which is `T1`
    signal t1_latch: std_ulogic := '0';
    --! `tres2_latch` (Phi1): `TRESX`, which is `TRES2`
    signal tres2_latch: std_ulogic := '0';
    --! `comp_latch2` (Phi1): `TWOCYCLE`
    signal comp_latch2: std_ulogic := '0';
    --! `t0_latch` (Phi2): `T0`, so it holds until `T1X`
    signal t0_latch: std_ulogic := '0';
    --! `t1x_latch` (Phi1): `T0` from the last cycle, which is `T1X`
    signal t1x_latch: std_ulogic := '0';

    -- Extended cycle counter

    --! The extended cycle counter's own copy of `T1` (Phi2), its shift input
    signal extra_t1_latch: std_ulogic := '0';
    --! `t2_latch1`-`t5_latch1` (Phi1): T2-T5 before `TRES2` clears them
    signal extra_latch1: std_ulogic_vector(5 downto 2) := (others => '0');
    --! `t2_latch2`-`t5_latch2` (Phi2): T2-T5, shifted into the next stage
    signal extra_latch2: std_ulogic_vector(5 downto 2) := (others => '0');

    -- Very long cycle counter

    --! `t67_latch` (Phi2): `SHIFT` and `MemOP` while ready, which starts `T6`
    signal t67_latch: std_ulogic := '0';
    --! `t6_latch1` (Phi1): `T6`
    signal t6_latch1: std_ulogic := '0';
    --! `t6_latch2` (Phi2): `T6`, so it holds while not ready
    signal t6_latch2: std_ulogic := '0';
    --! `t7_latch1` (Phi2): `T6` while ready, which starts `T7`
    signal t7_latch1: std_ulogic := '0';
    --! `t7_latch2` (Phi1): `T7`
    signal t7_latch2: std_ulogic := '0';

    signal T0: std_ulogic;
    signal T1: std_ulogic;
    signal TRES2: std_ulogic;
    signal extra_T: std_ulogic_vector(5 downto 2);
    signal T6: std_ulogic;
    --! The input to each extended counter stage: `T1`, then the stage before
    signal extra_shift_in: std_ulogic_vector(5 downto 2);
begin
    T1 <= t1_latch;
    TRES2 <= tres2_latch;

    -- Set when this is not T1 and either the next instruction takes 2 cycles,
    -- or the current one is finishing. Holds until T1X resets it.
    T0 <= (not T1 and (comp_latch2 or TRES2)) or (t0_latch and not t1x_latch);

    extra_T <= extra_latch1 and (5 downto 2 => not TRES2);
    extra_shift_in <= extra_latch2(4 downto 2) & extra_t1_latch;

    T6 <= t6_latch1;

    process(metaclock)
    begin
        if rising_edge(metaclock) then
            if phi1 = '1' then
                t1_latch <= reset_short_counter_TRES1;
                tres2_latch <= reset_counters_TRESX;
                comp_latch2 <= short_instruction_TWOCYCLE;
                t1x_latch <= t0_latch and ready;

                if ready = '1' then
                    extra_latch1 <= extra_shift_in;
                else
                    extra_latch1 <= extra_latch2;
                end if;

                t6_latch1 <= t67_latch or (t6_latch2 and not ready);
                t7_latch2 <= t7_latch1;
            end if;

            if phi2 = '1' then
                t0_latch <= T0;
                extra_t1_latch <= T1;
                extra_latch2 <= extra_T;
                t67_latch <= shift_instruction_SHIFT and memory_operation_MemOP and ready;
                t6_latch2 <= T6;
                t7_latch1 <= T6 and ready;
            end if;
        end if;
    end process;

    cycle_T0 <= T0;
    cycle_T1 <= T1;
    cycle_T1X <= t1x_latch;
    cycle_T2 <= extra_T(2);
    cycle_T3 <= extra_T(3);
    cycle_T4 <= extra_T(4);
    cycle_T5 <= extra_T(5);
    rmw_cycle_T6 <= T6;
    rmw_cycle_T7 <= t7_latch2;
end architecture rtl;
