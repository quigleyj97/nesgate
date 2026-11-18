module alu_formal (
    input [7:0] operand_a,
    input [7:0] operand_b,
    input carry_in,
    input decimal_enable,
    input enable_sum,
    input enable_and,
    input enable_xor,
    input enable_or,
    input enable_shift
);
    wire [7:0] result;
    wire carry_out;
    wire overflow;
    wire half_carry;

    mos_6502_alu dut (
        .a(operand_a),
        .b(operand_b),
        .carry_in_IADDC(carry_in),
        .decimal_enable_DAA(decimal_enable),
        .enable_sum_SUMS(enable_sum),
        .enable_and_ANDS(enable_and),
        .enable_xor_EORS(enable_xor),
        .enable_or_ORS(enable_or),
        .enable_right_shift_SRS(enable_shift),
        .result(result),
        .carry_out_ACR(carry_out),
        .overflow_AVR(overflow),
        .half_carry_HC(half_carry)
    );

    wire [8:0] unsigned_sum = {1'b0, operand_a}
        + {1'b0, operand_b} + {8'b0, carry_in};
    wire signed [9:0] signed_sum = $signed({{2{operand_a[7]}}, operand_a})
        + $signed({{2{operand_b[7]}}, operand_b}) + $signed({9'b0, carry_in});
    wire expected_overflow = signed_sum > 10'sd127 || signed_sum < -10'sd128;
    wire [4:0] operations = {enable_or, enable_xor, enable_and, enable_sum, enable_shift};

    always @* begin
        check_carry: assert (carry_out == unsigned_sum[8]);
        check_overflow: assert (overflow == expected_overflow);
        check_half_carry: assert (half_carry == 1'b0);

        if (enable_or) begin
            check_or: assert (result == (operand_a | operand_b));
            reach_or: cover (1'b1);
        end else if (enable_xor) begin
            check_xor: assert (result == (operand_a ^ operand_b));
            reach_xor: cover (1'b1);
        end else if (enable_and) begin
            check_and: assert (result == (operand_a & operand_b));
            reach_and: cover (1'b1);
        end else if (enable_sum) begin
            check_sum: assert (result == unsigned_sum[7:0]);
            reach_sum: cover (1'b1);
        end else if (enable_shift) begin
            check_shift: assert (result == ((operand_a & operand_b) >> 1));
            reach_shift: cover (1'b1);
        end else begin
            check_idle: assert (result == 8'b0);
            reach_idle: cover (1'b1);
        end

        reach_carry: cover (operations == 5'b00010 && carry_out && !overflow);
        reach_positive_overflow: cover (operations == 5'b00010
            && !operand_a[7] && !operand_b[7] && overflow);
        reach_negative_overflow: cover (operations == 5'b00010
            && operand_a[7] && operand_b[7] && overflow);
        reach_shift_mask: cover (operations == 5'b00001 && result != (operand_a >> 1));
        reach_priority: cover (operations == 5'b11111 && result != (operand_a ^ operand_b));
        reach_decimal_disabled: cover (operations == 5'b00010 && !decimal_enable && carry_in);
        reach_decimal_enabled: cover (operations == 5'b00010 && decimal_enable && carry_in);
    end
endmodule
