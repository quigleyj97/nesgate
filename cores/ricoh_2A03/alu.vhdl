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
        --! @ref Ricoh2A03_ALU_ACR
        carry_out_ACR: out std_ulogic;

        --! AVR - An output flag that is set when the signed result of an
        --! operation overflows.
        --! @ref Ricoh2A03_ALU_AVR
        overflow_AVR: out std_ulogic;

        --! HC - An output flag of unknown purpose
        --! @ref Ricoh2A03_ALU_HC
        half_carry_HC: out std_ulogic;

        -- Input signals

        --! Controls whether the ALU is in normal mode or BCD mode
        --! @ref Ricoh2A03_ALU_DAA
        decimal_enable_DAA: in std_ulogic;

        --! Carry-in input port for the ALU
        --! @ref Ricoh2A03_ALU_IADDC
        carry_in_IADDC: in std_ulogic;

        -- Operation mode signals

        --! Enable summing the inputs
        --! @ref Ricoh2A03_ALU_SUMS
        enable_sum_SUMS: in std_ulogic;

        --! Enable logical AND
        --! @ref Ricoh2A03_ALU_ANDS
        enable_and_ANDS: in std_ulogic;

        --! Enable logical XOR
        --! @ref Ricoh2A03_ALU_EORS
        enable_xor_EORS: in std_ulogic;

        --! Enable logical OR
        --! @ref Ricoh2A03_ALU_ORS
        enable_or_ORS: in std_ulogic;

        --! Enable right shift
        --! @ref Ricoh2A03_ALU_SRS
        enable_right_shift_SRS: in std_ulogic;
    );
end entity;