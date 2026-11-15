library ieee;
use ieee.std_logic_1164.all;

--! @file
--! @brief Predecode logic for the Ricoh 2A03
--! @details Combinational logic that classifies the opcode held in the
--! @ref predecode_register before it's loaded into the instruction register.
--!
--! - `TWOCYCLE` is set for instructions that finish in 2 cycles: immediate
--!   operand instructions (`XXX010X1` and `1XX000X0`), and single-byte
--!   instructions except the stack push/pull instructions (`XXXX10X0` but not
--!   `0XX0XX0X`).
--! - `IMPLIED` is set for single-byte instructions with no operand
--!   (`XXXX10X0`).
--!
--! `0/IR` forces the opcode to `0x00` (BRK), which is how interrupts inject
--! the BRK sequence into the instruction stream. It clears the opcode before
--! the classification logic, so neither output is set while it's asserted.
--!
--! The real chip produces `/TWOCYCLE`, `/IMPLIED` and an inverted opcode. This
--! core uses active-high signals and the true opcode throughout.

--! Predecode logic, deriving TWOCYCLE and IMPLIED from the predecoded opcode
entity predecode_logic is
    port(
        --! The opcode from @ref predecode_register
        predecode_in: in std_ulogic_vector(7 downto 0);
        --! @ref Ricoh_2A03_Signal_0_IR
        inject_brk_0_IR: in std_ulogic;
        --! The opcode, or BRK (`0x00`) while `0/IR` is asserted, fed to the
        --! instruction register
        predecode_out: out std_ulogic_vector(7 downto 0);
        --! @ref Ricoh_2A03_Signal_TWOCYCLE
        short_instruction_TWOCYCLE: out std_ulogic;
        --! @ref Ricoh_2A03_Signal_IMPLIED
        single_byte_IMPLIED: out std_ulogic
    );
end entity predecode_logic;

architecture rtl of predecode_logic is
    --! The opcode after BRK injection
    signal pd: std_ulogic_vector(7 downto 0);
    --! `XXXX10X0`: single-byte instructions
    signal implied: std_ulogic;
    --! `0XX0XX0X`: excludes the push/pull instructions from `implied`
    signal push_pull: std_ulogic;
    --! `XXX010X1`: immediate operand ALU instructions, e.g. `ORA #`
    signal immediate_alu: std_ulogic;
    --! `1XX000X0`: immediate operand index instructions, e.g. `LDY #`
    signal immediate_index: std_ulogic;
begin
    pd <= predecode_in and (7 downto 0 => not inject_brk_0_IR);

    implied <= pd(3) and not pd(2) and not pd(0);
    push_pull <= not pd(7) and not pd(4) and not pd(1);
    immediate_alu <= not pd(4) and pd(3) and not pd(2) and pd(0);
    immediate_index <= pd(7) and not pd(4) and not pd(3) and not pd(2) and not pd(0);

    predecode_out <= pd;
    single_byte_IMPLIED <= implied;
    short_instruction_TWOCYCLE <= (implied and not push_pull) or immediate_alu or immediate_index;
end architecture rtl;
