library ieee;
use ieee.std_logic_1164.all;

--! @file
--! @brief Instruction register (IR) for the MOS 6502
--! @details Holds the opcode currently being executed, for the decoder ROM and
--! the random logic.
--!
--! On the real chip, the IR loads the opcode from @ref predecode_logic during
--! @ref MOS_6502_Phi1, but only while @ref MOS_6502_Signal_FETCH is
--! asserted. During @ref MOS_6502_Phi2 it refreshes the value it holds. The
--! real IR takes the opcode inverted and also stores it inverted, then outputs
--! both polarities of each bit to the decoder. It merges `IR0` and `IR1` into a
--! single `IR01` line to save wiring, since `IR0` is only used by the 128th
--! decoder line (IMPL). `/IR5` also feeds the flag logic for the set/clear
--! instructions (SEI/CLI, SED/CLD, SEC/CLC).
--!
--! This core stores and outputs the opcode in true form only. Consumers derive
--! the inverted bits and `IR01` themselves.
--!
--! FPGA fabric can't synthesize a level-sensitive latch cleanly, so Phi1 and
--! `FETCH` are sampled on the @ref metaclock instead. While both are high the
--! register follows the predecoded opcode one metaclock behind, and holds the
--! last value it saw before either fell. The Phi2 refresh only keeps the real
--! chip's dynamic latch from leaking, so it has no equivalent here.

--! Instruction register, loaded from the predecode logic during Phi1 while
--! FETCH is asserted
entity instruction_register is
    port(
        --! @ref MOS_6502_Phi1. The register can only load while high
        phi1: in std_ulogic;
        --! @ref MOS_6502_Signal_FETCH
        load_opcode_FETCH: in std_ulogic;
        --! The opcode from @ref predecode_logic
        predecode_in: in std_ulogic_vector(7 downto 0);
        --! The current opcode, maps to IR0-IR7
        instruction_out: out std_ulogic_vector(7 downto 0);
        --! Clock to drive the latch circuitry
        --! @ref metaclock
        metaclock: in std_ulogic
    );
end entity instruction_register;

architecture rtl of instruction_register is
    signal register_value: std_ulogic_vector(7 downto 0) := (others => '0');
begin
    process(metaclock)
    begin
        if rising_edge(metaclock) then
            if phi1 = '1' and load_opcode_FETCH = '1' then
                register_value <= predecode_in;
            end if;
        end if;
    end process;

    instruction_out <= register_value;
end architecture rtl;
