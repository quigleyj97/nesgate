// Properties of the bus multiplexer, for every possible input at one
// instant. Each drive_* input is every driver of that bus already ANDed
// together by the datapath, so a 1 means nothing pulls that bit low.
//
// The model is written in terms of what pulls each bit low. A bit of a bus
// reads 0 exactly when something on the node it belongs to pulls it low:
// its own drivers, its open drain MOSFETs, or any bus the pass MOSFETs join
// it to.
module bus_multiplexer_formal (
    input [7:0] drive_sb,
    input [7:0] drive_db,
    input [7:0] drive_adh,
    input [7:0] drive_adl,
    input sb_db,
    input sb_adh,
    input zero_adl0,
    input zero_adl1,
    input zero_adl2,
    input zero_adh0,
    input zero_adh_1_7
);
    wire [7:0] bus_sb;
    wire [7:0] bus_db;
    wire [7:0] bus_adh;
    wire [7:0] bus_adl;

    bus_multiplexer dut (
        .drive_SB(drive_sb),
        .drive_DB(drive_db),
        .drive_ADH(drive_adh),
        .drive_ADL(drive_adl),
        .connect_SB_DB(sb_db),
        .connect_SB_ADH(sb_adh),
        .clear_0_ADL0(zero_adl0),
        .clear_0_ADL1(zero_adl1),
        .clear_0_ADL2(zero_adl2),
        .clear_0_ADH0(zero_adh0),
        .clear_0_ADH_1_7(zero_adh_1_7),
        .bus_SB(bus_sb),
        .bus_DB(bus_db),
        .bus_ADH(bus_adh),
        .bus_ADL(bus_adl)
    );

    // The bits each bus's own drivers and open drain MOSFETs pull low
    wire [7:0] low_sb = ~drive_sb;
    wire [7:0] low_db = ~drive_db;
    wire [7:0] low_adh = ~drive_adh | {{7{zero_adh_1_7}}, zero_adh0};
    wire [7:0] low_adl = ~drive_adl | {5'b0, zero_adl2, zero_adl1, zero_adl0};
    // The bits pulled low anywhere on the node SB belongs to
    wire [7:0] low_sb_node = low_sb
        | (sb_db ? low_db : 8'b0)
        | (sb_adh ? low_adh : 8'b0);

    always @* begin
        check_sb: assert (bus_sb == ~low_sb_node);
        check_db: assert (bus_db == ~(sb_db ? low_sb_node : low_db));
        check_adh: assert (bus_adh == ~(sb_adh ? low_sb_node : low_adh));
        check_adl: assert (bus_adl == ~low_adl);

        // A bus joined to SB through a pass MOSFET always reads the same as
        // SB, so DB and ADH are joined through SB when both are on
        if (sb_db) check_sb_db_joined: assert (bus_db == bus_sb);
        if (sb_adh) check_sb_adh_joined: assert (bus_adh == bus_sb);
        // Nothing reaches ADL from another bus
        check_adl_isolated: assert (bus_adl == (drive_adl
            & {5'h1f, ~zero_adl2, ~zero_adl1, ~zero_adl0}));

        // Every bus idle: all precharged
        reach_idle: cover (bus_sb == 8'hff && bus_db == 8'hff
            && bus_adh == 8'hff && bus_adl == 8'hff && !sb_db && !sb_adh);
        // The open drain MOSFETs alone form the low byte of the NMI vector
        // (0xFFFA) and a zero page high byte
        reach_nmi_vector: cover (drive_adl == 8'hff && bus_adl == 8'hfa);
        reach_zero_page: cover (drive_adh == 8'hff && !sb_adh
            && bus_adh == 8'h00);
        // Something on DB pulls SB low through SB/DB
        reach_db_into_sb: cover (sb_db && !sb_adh && low_sb == 8'b0
            && bus_sb != 8'hff);
        // ADH pulls DB low through SB, with both pass MOSFETs on
        reach_adh_into_db: cover (sb_db && sb_adh && low_sb == 8'b0
            && low_db == 8'b0 && bus_db != 8'hff);
        // DB stays apart from SB while SB/DB is off
        reach_isolated: cover (!sb_db && bus_db != bus_sb);
    end
endmodule
