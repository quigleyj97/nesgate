// End-to-end properties of the logic core, phase by phase, with real
// Phi1/Phi2 clocks (two_phase_clock.sv): the A and B input registers, the
// ALU, the adder hold register, and the ACR and AVR latches, wired together.
//
// The harness keeps no model of the netlist's registers. ACR and AVR are
// outputs, so each property relates them at the end of a phase to their
// values at the end of the phase before. The A and B input registers and the
// adder hold register aren't outputs (the hold register only shows through
// its bus ports), so the harness follows them as logic_core.vhdl documents
// them, a phase at a time:
//
// - During Phi1, A takes SB (SB/ADD) or 0 (0/ADD), and B takes DB inverted
//   (NOT(DB)/ADD), DB (DB/ADD) or ADL (ADL/ADD). Each holds while none of
//   its loads is selected. Both hold through Phi2.
// - During Phi2, the hold register, ACR and AVR take the ALU's result, carry
//   and overflow from A and B, from the textbook definitions (as in
//   alu_formal.sv). All three hold through Phi1.
// - ADD/SB(0-6), ADD/SB(7) and ADD/ADL drive the hold register onto their
//   own bits, and a disabled port drives all ones, releasing the bus.
// - HC is always 0.
//
// The random logic loads A and B only outside Phi2, so the harness assumes
// the same. It also assumes at most one load per register and at most one
// operation at a time: what the subunits do with several at once is their
// own proofs' business (a_input_register_formal.sv, b_input_register_formal.sv
// and alu_formal.sv). Each input changes only as a phase starts. Everything
// powers up as 0.
module logic_core_formal (
    input metaclock,
    input end_phase,

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
    wire phi1, phi2, first_edge, last_edge;
    two_phase_clock clock (
        .metaclock(metaclock),
        .end_phase(end_phase),
        .phi1(phi1),
        .phi2(phi2),
        .first_edge(first_edge),
        .last_edge(last_edge)
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

    // #region Inputs
    wire [4:0] f_loads = {not_db_add, db_add, adl_add, sb_add, zero_add};
    wire [4:0] f_operations = {sums, ands, ors, eors, srs};
    wire [43:0] f_inputs = {adl_bus_in, sb_bus_in, db_bus_in, f_loads,
        daa, i_addc, f_operations, add_sb_0_6, add_sb_7, add_adl};

    // Each input only changes as a phase starts
    reg f_past_valid = 1'b0;
    reg [43:0] f_inputs_was = 44'b0;
    always @(posedge metaclock) begin
        f_past_valid <= 1'b1;
        f_inputs_was <= f_inputs;
    end

    function at_most_one(input [4:0] bits);
        at_most_one = (bits & (bits - 5'd1)) == 5'b0;
    endfunction

    always @* begin
        if (f_past_valid && !first_edge) begin
            assume_inputs_hold: assume (f_inputs == f_inputs_was);
        end
        assume_one_a_load: assume (!(sb_add && zero_add));
        assume_one_b_load: assume (at_most_one({2'b0, not_db_add, db_add, adl_add}));
        assume_one_operation: assume (at_most_one(f_operations));
        if (phi2) begin
            assume_no_load_phi2: assume (f_loads == 5'b0);
        end
    end
    // #endregion

    // #region ALU
    // The textbook definitions, as in alu_formal.sv
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

    // At most one operation is selected, so the order here doesn't matter
    function [7:0] spec_result(
        input [7:0] a, input [7:0] b, input carry_in,
        input op_or, input op_xor, input op_and, input op_sum, input op_shift
    );
        reg [8:0] sum;
        begin
            sum = spec_sum(a, b, carry_in);
            spec_result = op_or ? a | b
                : op_xor ? a ^ b
                : op_and ? a & b
                : op_sum ? sum[7:0]
                : op_shift ? (a & b) >> 1
                : 8'b0;
        end
    endfunction
    // #endregion

    // #region Registers
    // A and B at the end of the last Phi1, the hold register at the end of
    // the last Phi2, and the flags at the end of the phase before
    reg [7:0] f_a = 8'b0;
    reg [7:0] f_b = 8'b0;
    reg [7:0] f_hold = 8'b0;
    reg f_carry_phase = 1'b0;
    reg f_overflow_phase = 1'b0;

    wire [7:0] f_a_next = sb_add ? sb_bus_in : zero_add ? 8'b0 : f_a;
    wire [7:0] f_b_next = not_db_add ? ~db_bus_in
        : db_add ? db_bus_in
        : adl_add ? adl_bus_in
        : f_b;

    // The ALU's outputs during Phi2, from A and B
    wire [8:0] f_sum = spec_sum(f_a, f_b, i_addc);
    wire [7:0] f_result = spec_result(f_a, f_b, i_addc, ors, eors, ands, sums, srs);
    wire f_overflow = spec_overflow(f_a, f_b, i_addc);

    always @(posedge metaclock) begin
        if (phi1 && last_edge) begin
            f_a <= f_a_next;
            f_b <= f_b_next;
        end
        if (phi2 && last_edge) f_hold <= f_result;
        if (last_edge) begin
            f_carry_phase <= signal_carry;
            f_overflow_phase <= signal_avr;
        end
    end
    // #endregion

    // What the hold register puts on SB and ADL
    function [7:0] sb_port(input [7:0] value);
        sb_port = {add_sb_7 ? value[7] : 1'b1, add_sb_0_6 ? value[6:0] : 7'h7f};
    endfunction
    function [7:0] adl_port(input [7:0] value);
        adl_port = add_adl ? value : 8'hff;
    endfunction

    always @* begin
        check_half_carry: assert (signal_hc == 1'b0);
        // The hold register, ACR and AVR hold through Phi1, while A and B load
        if (phi1) begin
            check_sb_phi1: assert (sb_bus_out == sb_port(f_hold));
            check_adl_phi1: assert (adl_bus_out == adl_port(f_hold));
            check_carry_phi1: assert (signal_carry == f_carry_phase);
            check_overflow_phi1: assert (signal_avr == f_overflow_phase);
        end
        // The end of Phi2: the ALU's result, carry and overflow from A and B
        if (phi2 && last_edge) begin
            check_sb_phi2: assert (sb_bus_out == sb_port(f_result));
            check_adl_phi2: assert (adl_bus_out == adl_port(f_result));
            check_carry_phi2: assert (signal_carry == f_sum[8]);
            check_overflow_phi2: assert (signal_avr == f_overflow);
        end
    end

    always @* begin
        if (phi2 && last_edge) begin
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
            // SBC: NOT(DB) into B, so A - DB
            reach_subtract: cover (sums && f_a == 8'h05 && f_b == 8'hfc && i_addc
                && add_adl && adl_bus_out == 8'h02 && signal_carry);
        end
        if (phi1 && last_edge) begin
            // The hold register and flags keep their values while A and B
            // load operands that would change them
            reach_hold: cover (add_adl && sb_add && db_add
                && adl_bus_out != 8'hff && adl_bus_out != 8'h00
                && f_a_next != f_a && f_b_next != f_b && signal_carry);
        end
    end
endmodule
