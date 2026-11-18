// Properties of the stack pointer, checked on every metaclock edge. The SB
// and ADL ports go through the same precharge techmap as synthesis (see
// techmaps/precharge_tribuf.v), so a disabled port reads all ones.
module stack_pointer_formal (
    input metaclock,
    input phi2,
    input sb_s,
    input s_sb,
    input s_adl,
    input [7:0] sb_in
);
    wire [7:0] sb_out;
    wire [7:0] adl_out;

    stack_pointer dut (
        .phi2(phi2),
        .signal_S_SB(s_sb),
        .signal_S_ADL(s_adl),
        .signal_SB_S(sb_s),
        .bus_SB_in(sb_in),
        .bus_SB_out(sb_out),
        .bus_ADL(adl_out),
        .metaclock(metaclock)
    );

    // A model of the two stages, both powering up as 0. On each metaclock
    // edge, the input latch takes SB while SB/S is high, and the output latch
    // takes the input latch's old value while Phi2 is high.
    reg [7:0] f_input = 8'b0;
    reg [7:0] f_output = 8'b0;
    always @(posedge metaclock) begin
        if (sb_s) f_input <= sb_in;
        if (phi2) f_output <= f_input;
    end

    always @* begin
        check_sb: assert (sb_out == (s_sb ? f_output : 8'hff));
        check_adl: assert (adl_out == (s_adl ? f_output : 8'hff));
    end

    reg f_past_valid = 1'b0;
    always @(posedge metaclock) f_past_valid <= 1'b1;

    always @(posedge metaclock) begin
        if (f_past_valid) begin
            // A value loaded from SB reaches the outputs during a later Phi2
            reach_load: cover (!$past(sb_s) && $past(phi2) && s_adl
                && adl_out != 8'b0 && adl_out != 8'hff);
            // JSR: S keeps driving its old value onto ADL while it loads a
            // new one
            reach_old_while_loading: cover ($past(sb_s) && !$past(phi2) && s_adl
                && adl_out != 8'hff && adl_out != f_input);
            reach_sb_only: cover (s_sb && !s_adl && sb_out != 8'hff);
        end
    end
endmodule
