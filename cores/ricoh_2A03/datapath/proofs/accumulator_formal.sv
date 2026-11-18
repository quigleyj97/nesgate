// Properties of the accumulator, checked on every metaclock edge. The SB and
// DB ports go through the same precharge techmap as synthesis (see
// techmaps/precharge_tribuf.v), so a disabled port reads all ones.
module accumulator_formal (
    input metaclock,
    input load_sb_ac,
    input ac_sb,
    input ac_db,
    input [7:0] sb_in
);
    wire [7:0] sb_out;
    wire [7:0] db_out;

    accumulator dut (
        .databus_SB_in(sb_in),
        .databus_SB_out(sb_out),
        .databus_DB(db_out),
        .load_SB_AC(load_sb_ac),
        .output_enable_AC_SB(ac_sb),
        .output_enable_AC_DB(ac_db),
        .metaclock(metaclock)
    );

    // A model of the accumulator: it powers up as 0, takes SB on each
    // metaclock edge while SB/AC is high, and holds otherwise
    reg [7:0] f_value = 8'b0;
    always @(posedge metaclock) begin
        if (load_sb_ac) f_value <= sb_in;
    end

    always @* begin
        check_sb: assert (sb_out == (ac_sb ? f_value : 8'hff));
        check_db: assert (db_out == (ac_db ? f_value : 8'hff));
    end

    reg f_past_valid = 1'b0;
    always @(posedge metaclock) f_past_valid <= 1'b1;

    always @(posedge metaclock) begin
        if (f_past_valid) begin
            reach_load: cover ($past(load_sb_ac) && ac_db
                && db_out != 8'b0 && db_out != 8'hff);
            reach_hold: cover (!$past(load_sb_ac) && ac_sb
                && sb_out != 8'b0 && sb_out != $past(sb_in));
            reach_sb_only: cover (ac_sb && !ac_db && sb_out != 8'hff);
            reach_db_only: cover (!ac_sb && ac_db && db_out != 8'hff);
            reach_both: cover (ac_sb && ac_db && sb_out != 8'hff);
        end
    end
endmodule
