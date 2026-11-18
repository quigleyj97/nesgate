// End-to-end properties of the logic core: the A and B input registers, the
// ALU, the adder hold register, and the ACR and AVR latches, wired together.
//
// Every register in the core is on the metaclock: the input registers, the
// adder hold register and the ACR/AVR latches. The last three load while
// Phi2 is high, so they always hold the result, carry and overflow of the
// same operands. The proof runs with SymbiYosys's multiclock mode so that
// the metaclock is an ordinary input: every step is a tick of the global
// formal clock, and the metaclock and Phi2 can change on any step, in any
// order, independently of each other.
//
// The harness keeps a model of every register, built from the textbook
// definitions below, and checks the core's outputs against it on every step.
// The registers that aren't outputs (A and B) are only checked through what
// they do to the outputs. A disabled bus port drives all ones (released).
module logic_core_formal (
    input metaclock,
    input phi2,

    input [7:0] adl_bus_in,
    input [7:0] sb_bus_in,
    input [7:0] db_bus_in,

    input not_db_add,
    input db_add,
    input adl_add,
    input sb_add,
    input zero_add,

    input daa,
    input i_addc,
    input sums,
    input ands,
    input ors,
    input eors,
    input srs,

    input add_sb_0_6,
    input add_sb_7,
    input add_adl
);
    wire [7:0] adl_bus_out;
    wire [7:0] sb_bus_out;
    wire signal_avr;
    wire signal_carry;
    wire signal_hc;

    logic_core dut (
        .adl_bus_in(adl_bus_in),
        .adl_bus_out(adl_bus_out),
        .sb_bus_in(sb_bus_in),
        .sb_bus_out(sb_bus_out),
        .db_bus_in(db_bus_in),
        .control_not_db_add(not_db_add),
        .control_db_add(db_add),
        .control_adl_add(adl_add),
        .control_sb_add(sb_add),
        .control_0_add(zero_add),
        .control_daa(daa),
        .control_i_addc(i_addc),
        .control_sums(sums),
        .control_ands(ands),
        .control_ors(ors),
        .control_eors(eors),
        .control_srs(srs),
        .signal_avr(signal_avr),
        .signal_carry(signal_carry),
        .signal_hc(signal_hc),
        .control_add_sb_0_6(add_sb_0_6),
        .control_add_sb_7(add_sb_7),
        .control_add_adl(add_adl),
        .metaclock(metaclock),
        .phi2(phi2)
    );

    // The ALU, from the textbook definitions (see alu_formal.sv)
    function [8:0] spec_sum(input [7:0] a, input [7:0] b, input carry_in);
        spec_sum = {1'b0, a} + {1'b0, b} + {8'b0, carry_in};
    endfunction

    function spec_overflow(input [7:0] a, input [7:0] b, input carry_in);
        reg [8:0] sum;
        begin
            sum = spec_sum(a, b, carry_in);
            spec_overflow = a[7] == b[7] && sum[7] != a[7];
        end
    endfunction

    function [7:0] spec_result(
        input [7:0] a, input [7:0] b, input carry_in,
        input op_or, input op_xor, input op_and, input op_sum, input op_shift
    );
        reg [8:0] sum;
        begin
            sum = spec_sum(a, b, carry_in);
            if (op_or) spec_result = a | b;
            else if (op_xor) spec_result = a ^ b;
            else if (op_and) spec_result = a & b;
            else if (op_sum) spec_result = sum[7:0];
            else if (op_shift) spec_result = (a & b) >> 1;
            else spec_result = 8'b0;
        end
    endfunction

    // Every input as it was on the step before
    reg f_past_valid = 1'b0;
    reg f_metaclock_was = 1'b0;
    reg f_phi2_was = 1'b0;
    reg [7:0] f_adl_was = 8'b0;
    reg [7:0] f_sb_was = 8'b0;
    reg [7:0] f_db_was = 8'b0;
    reg f_not_db_add_was = 1'b0;
    reg f_db_add_was = 1'b0;
    reg f_adl_add_was = 1'b0;
    reg f_sb_add_was = 1'b0;
    reg f_zero_add_was = 1'b0;
    reg f_i_addc_was = 1'b0;
    reg f_sums_was = 1'b0;
    reg f_ands_was = 1'b0;
    reg f_ors_was = 1'b0;
    reg f_eors_was = 1'b0;
    reg f_srs_was = 1'b0;

    // The model's registers as they were on the step before
    reg [7:0] f_a_was = 8'b0;
    reg [7:0] f_b_was = 8'b0;
    reg [7:0] f_hold_was = 8'b0;
    reg f_acr_was = 1'b0;
    reg f_avr_was = 1'b0;

    // A register samples what its inputs were just before the clock edge
    wire f_metaclock_rose = metaclock && !f_metaclock_was;

    // The A and B input registers load on the metaclock
    wire [7:0] f_a = !f_metaclock_rose ? f_a_was
        : f_sb_add_was ? f_sb_was
        : f_zero_add_was ? 8'b0
        : f_a_was;
    wire [7:0] f_b = !f_metaclock_rose ? f_b_was
        : f_not_db_add_was ? ~f_db_was
        : f_db_add_was ? f_db_was
        : f_adl_add_was ? f_adl_was
        : f_b_was;

    // The ALU's outputs on the step before, from the A and B registers
    wire [8:0] f_sum_was = spec_sum(f_a_was, f_b_was, f_i_addc_was);
    wire [7:0] f_result_was = spec_result(f_a_was, f_b_was, f_i_addc_was,
        f_ors_was, f_eors_was, f_ands_was, f_sums_was, f_srs_was);

    // The adder hold register and the ACR and AVR latches load on the
    // metaclock while Phi2 is high
    wire f_phi2_load = f_metaclock_rose && f_phi2_was;
    wire [7:0] f_hold = f_phi2_load ? f_result_was : f_hold_was;
    wire f_acr = f_phi2_load ? f_sum_was[8] : f_acr_was;
    wire f_avr = f_phi2_load
        ? spec_overflow(f_a_was, f_b_was, f_i_addc_was) : f_avr_was;

    always @($global_clock) begin
        f_past_valid <= 1'b1;
        f_metaclock_was <= metaclock;
        f_phi2_was <= phi2;
        f_adl_was <= adl_bus_in;
        f_sb_was <= sb_bus_in;
        f_db_was <= db_bus_in;
        f_not_db_add_was <= not_db_add;
        f_db_add_was <= db_add;
        f_adl_add_was <= adl_add;
        f_sb_add_was <= sb_add;
        f_zero_add_was <= zero_add;
        f_i_addc_was <= i_addc;
        f_sums_was <= sums;
        f_ands_was <= ands;
        f_ors_was <= ors;
        f_eors_was <= eors;
        f_srs_was <= srs;

        f_a_was <= f_a;
        f_b_was <= f_b;
        f_hold_was <= f_hold;
        f_acr_was <= f_acr;
        f_avr_was <= f_avr;
    end

    always @* begin
        if (!f_past_valid) begin
            assume_power_up: assume (!metaclock && !phi2);
        end

        check_sb_0_6: assert (sb_bus_out[6:0] == (add_sb_0_6 ? f_hold[6:0] : 7'h7f));
        check_sb_7: assert (sb_bus_out[7] == (add_sb_7 ? f_hold[7] : 1'b1));
        check_adl: assert (adl_bus_out == (add_adl ? f_hold : 8'hff));
        check_carry: assert (signal_carry == f_acr);
        check_overflow: assert (signal_avr == f_avr);
        check_half_carry: assert (signal_hc == 1'b0);

        // 0x7F + 0x01 = 0x80: an add, through the hold register onto SB,
        // with signed overflow latched in AVR
        reach_add_overflow: cover (add_sb_0_6 && add_sb_7
            && sb_bus_out == 8'h80 && signal_avr && !signal_carry);
        // A result onto ADL with the carry latched in ACR
        reach_carry_out: cover (add_adl && adl_bus_out != 8'hff
            && adl_bus_out != 8'h00 && signal_carry && !signal_avr);
        // ROR's split: bits 0-6 onto SB, bit 7 held back (precharged)
        reach_split_sb: cover (add_sb_0_6 && !add_sb_7
            && sb_bus_out[6:0] != 7'h7f);
        // The hold register keeps its result while the ALU's output changes
        reach_hold: cover (f_past_valid && !f_phi2_load && add_adl
            && adl_bus_out != 8'hff && adl_bus_out != f_result_was);
        // The flags keep their value while Phi2 is low
        reach_flags_held: cover (f_metaclock_rose && !f_phi2_was
            && signal_carry != f_sum_was[8]);
    end
endmodule
