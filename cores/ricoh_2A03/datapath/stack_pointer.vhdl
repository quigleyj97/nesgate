library ieee;
use ieee.std_logic_1164.all;

--! @file
--! @brief The Stack Pointer register (S) from the MOS 6502 CPU
--! @details Like the real register, S has two stages:
--!
--! - The input latch loads from SB while @ref Ricoh_2A03_Signal_SB_S is
--!   asserted (during Phi1). Otherwise it's refreshed from the output latch
--!   (@ref Ricoh_2A03_Signal_S_S), which on FPGA fabric just means it holds.
--! - The output latch loads from the input latch during Phi2, and drives SB
--!   (`S/SB`) and ADL (`S/ADL`).
--!
--! So a value loaded during Phi1 only reaches the outputs in Phi2, and S can
--! drive its old value onto a bus during the same Phi1 it loads a new one.
--! JSR relies on that: it parks the target's low byte in S, while S is still
--! addressing the stack.
--!
--! Both latches are sampled on the @ref metaclock while their phase or load
--! signal is high, like the rest of this core's latches.
entity stack_pointer is
    port(
        --! @ref Ricoh_2A03_Phi2. The output latch loads while this is high.
        phi2: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_S_SB
        signal_S_SB: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_S_ADL
        signal_S_ADL: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_SB_S
        signal_SB_S: in std_ulogic;
        --! @ref Ricoh_2A03_SB, as resolved by @ref bus_multiplexer
        bus_SB_in: in std_ulogic_vector(7 downto 0);
        --! Drives @ref Ricoh_2A03_SB, 'Z' when not enabled
        bus_SB_out: out std_ulogic_vector(7 downto 0);
        --! Drives @ref Ricoh_2A03_ADL, 'Z' when not enabled
        bus_ADL: out std_ulogic_vector(7 downto 0);
        --! Clock to drive the latch circuitry
        --! @ref metaclock
        metaclock: in std_ulogic
    );
end entity stack_pointer;

architecture rtl of stack_pointer is
    --! The input latch, loaded from SB
    signal input_latch: std_ulogic_vector(7 downto 0) := (others => '0');
    --! The output latch, loaded from the input latch during Phi2
    signal register_value: std_ulogic_vector(7 downto 0) := (others => '0');
begin
    process(metaclock)
    begin
        if rising_edge(metaclock) then
            if signal_SB_S = '1' then
                input_latch <= bus_SB_in;
            end if;
            if phi2 = '1' then
                register_value <= input_latch;
            end if;
        end if;
    end process;
    bus_SB_out <= register_value when signal_S_SB = '1' else (others => 'Z');
    bus_ADL <= register_value when signal_S_ADL = '1' else (others => 'Z');
end architecture rtl;
