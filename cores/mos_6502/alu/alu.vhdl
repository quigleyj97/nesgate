library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity mos_6502_alu is
    port (
        --! The A input register for the ALU
        a: in std_ulogic_vector(7 downto 0);

        --! The B input register for the ALU
        b: in std_ulogic_vector(7 downto 0);

        --! The output word from the ALU
        result: out std_ulogic_vector(7 downto 0);

        -- Output signals

        --! ACR - An output flag that is true if the result is > 255
        --! @ref MOS6502_ALU_ACR
        carry_out_ACR: out std_ulogic;

        --! AVR - An output flag that is set when the signed result of an
        --! operation overflows.
        --! @ref MOS6502_ALU_AVR
        overflow_AVR: out std_ulogic;

        --! HC - An output flag of unknown purpose
        --! @ref MOS6502_ALU_HC
        half_carry_HC: out std_ulogic;

        -- Input signals

        --! Controls whether the ALU is in normal mode or BCD mode
        --! @ref MOS6502_ALU_DAA
        decimal_enable_DAA: in std_ulogic;

        --! Carry-in input port for the ALU
        --! @ref MOS6502_ALU_IADDC
        carry_in_IADDC: in std_ulogic;

        -- Operation mode signals

        --! Enable summing the inputs
        --! @ref MOS6502_ALU_SUMS
        enable_sum_SUMS: in std_ulogic;

        --! Enable logical AND
        --! @ref MOS6502_ALU_ANDS
        enable_and_ANDS: in std_ulogic;

        --! Enable logical XOR
        --! @ref MOS6502_ALU_EORS
        enable_xor_EORS: in std_ulogic;

        --! Enable logical OR
        --! @ref MOS6502_ALU_ORS
        enable_or_ORS: in std_ulogic;

        --! Enable right shift
        --! @ref MOS6502_ALU_SRS
        enable_right_shift_SRS: in std_ulogic
    );
end entity;

architecture rtl of mos_6502_alu is
    -- Some internal signals to make carry and overflow calculations easier
    -- These are <carryout>,<8 to 1:register 7 to 0><carryin>
    signal a_register_extended: std_ulogic_vector(9 downto 0) := (others => '0');
    signal b_register_extended: std_ulogic_vector(9 downto 0) := (others => '0');
    signal sum_register: std_ulogic_vector(9 downto 0) := (others => '0');

    --! Shifts right by one, shifting in a 0. The random logic rotates the
    --! carry into bit 7 by holding back `ADD/SB(7)`.
    function shift_right(value: std_ulogic_vector(7 downto 0)) return std_ulogic_vector is
    begin
        return '0' & value(7 downto 1);
    end function;
begin
    a_register_extended <= std_ulogic_vector('0' & a & '1');
    b_register_extended <= std_ulogic_vector('0' & b & '1') when carry_in_IADDC = '1'
        else std_ulogic_vector('0' & b & '0');
    sum_register <= std_ulogic_vector(unsigned(a_register_extended) + unsigned(b_register_extended));

    result <= a or b when enable_or_ORS = '1' else
              a xor b when enable_xor_EORS = '1' else
              a and b when enable_and_ANDS = '1' else
              std_ulogic_vector(sum_register(8 downto 1)) when enable_sum_SUMS = '1' else
              -- The shifter reuses the AND gates, so it shifts A AND B. For a
              -- shift of one operand, the other input is all ones (an
              -- undriven, precharged bus)
              shift_right(a and b) when enable_right_shift_SRS = '1' else
              (others => '0');
    
    carry_out_ACR <= sum_register(9);
    overflow_AVR <= (a(7) xor sum_register(8)) and (b(7) xor sum_register(8));
    half_carry_HC <= '0';

end rtl;