// Properties of the adder hold register. It loads on the rising edge of its
// load input (Phi2), not on the metaclock, so the proof runs with SymbiYosys's
// multiclock mode: every step is a tick of the global formal clock, and load
// is an ordinary input that can rise on any step.
//
// The tri-state ports go through the same precharge techmap as synthesis
// (see techmaps/precharge_tribuf.v), so a disabled port reads all ones.
module adder_hold_register_formal (
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
        .adl_bus_port(adl_bus)
    );

    // A model of the register: on a rising edge of load it takes the value
    // data_in had on the step before, otherwise it holds
    reg f_past_valid = 1'b0;
    reg f_load_was = 1'b0;
    reg [7:0] f_data_was = 8'b0;
    reg [7:0] f_held = 8'b0;
    wire f_load_rose = load && !f_load_was;
    wire [7:0] f_expected = f_load_rose ? f_data_was : f_held;

    always @($global_clock) begin
        f_past_valid <= 1'b1;
        f_load_was <= load;
        f_data_was <= data_in;
        f_held <= f_expected;
    end

    always @* begin
        if (!f_past_valid) begin
            assume_power_up: assume (!load);
        end

        check_sb_0_6: assert (sb_bus[6:0] == (enable_sb_0_6 ? f_expected[6:0] : 7'h7f));
        check_sb_7: assert (sb_bus[7] == (enable_sb_7 ? f_expected[7] : 1'b1));
        check_adl: assert (adl_bus == (enable_adl ? f_expected : 8'hff));

        reach_load: cover (f_load_rose && enable_adl && adl_bus != 8'hff);
        reach_hold_while_high: cover (load && f_load_was && enable_adl
            && adl_bus != f_data_was);
        reach_sb_0_6_only: cover (enable_sb_0_6 && !enable_sb_7
            && sb_bus[6:0] != 7'h7f);
        reach_sb_7_only: cover (!enable_sb_0_6 && enable_sb_7 && !sb_bus[7]);
        reach_both_buses: cover (enable_sb_0_6 && enable_sb_7 && enable_adl
            && sb_bus == adl_bus && adl_bus != 8'hff);
    end
endmodule
