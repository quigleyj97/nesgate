// Properties of the adder hold register, checked on every metaclock edge. It
// takes data_in on each edge while load (Phi2) is high, and holds otherwise.
//
// The tri-state ports go through the same precharge techmap as synthesis
// (see techmaps/precharge_tribuf.v), so a disabled port reads all ones.
module adder_hold_register_formal (
    input metaclock,
    input load,
    input [7:0] data_in,
    input enable_sb_0_6,
    input enable_sb_7,
    input enable_adl
);
    wire [7:0] sb_bus;
    wire [7:0] adl_bus;

    adder_hold_register dut (
        .load(load),
        .data_in(data_in),
        .sb_bus_enable_ADD_SB_0_6(enable_sb_0_6),
        .sb_bus_enable_ADD_SB_7(enable_sb_7),
        .sb_bus_port(sb_bus),
        .adl_bus_enable_ADD_ADL(enable_adl),
        .adl_bus_port(adl_bus),
        .metaclock(metaclock)
    );

    // A model of the register, which powers up as 0
    reg f_past_valid = 1'b0;
    reg [7:0] f_held = 8'b0;
    always @(posedge metaclock) begin
        f_past_valid <= 1'b1;
        if (load) f_held <= data_in;
    end

    always @* begin
        check_sb_0_6: assert (sb_bus[6:0] == (enable_sb_0_6 ? f_held[6:0] : 7'h7f));
        check_sb_7: assert (sb_bus[7] == (enable_sb_7 ? f_held[7] : 1'b1));
        check_adl: assert (adl_bus == (enable_adl ? f_held : 8'hff));

        reach_sb_0_6_only: cover (enable_sb_0_6 && !enable_sb_7
            && sb_bus[6:0] != 7'h7f);
        reach_sb_7_only: cover (!enable_sb_0_6 && enable_sb_7 && !sb_bus[7]);
        reach_both_buses: cover (enable_sb_0_6 && enable_sb_7 && enable_adl
            && sb_bus == adl_bus && adl_bus != 8'hff);
    end

    always @(posedge metaclock) begin
        if (f_past_valid) begin
            reach_load: cover ($past(load) && enable_adl && adl_bus != 8'hff
                && adl_bus != $past(f_held));
            // Phi2 is low: the input changes, but the register holds
            reach_hold: cover (!$past(load) && enable_adl && adl_bus != 8'hff
                && adl_bus != $past(data_in));
            // Phi2 stays high: the register follows its input
            reach_follow: cover ($past(load) && $past(load, 2) && enable_adl
                && adl_bus != $past(f_held) && $past(f_held) != $past(f_held, 2));
        end
    end
endmodule
