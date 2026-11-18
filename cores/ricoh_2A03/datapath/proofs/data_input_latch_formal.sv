// Properties of the data input latch, checked on every metaclock edge. A
// disabled DB, ADH or ADL port drives all ones, releasing the bus.
module data_input_latch_formal (
    input metaclock,
    input load,
    input [7:0] data_in,
    input dl_db,
    input dl_adh,
    input dl_adl
);
    wire [7:0] db_out;
    wire [7:0] adh_out;
    wire [7:0] adl_out;

    data_input_latch dut (
        .load(load),
        .data_in(data_in),
        .db_bus_enable_DL_DB(dl_db),
        .db_bus_port(db_out),
        .adh_bus_enable_DL_ADH(dl_adh),
        .adh_bus_port(adh_out),
        .adl_bus_enable_DL_ADL(dl_adl),
        .adl_bus_port(adl_out),
        .metaclock(metaclock)
    );

    // A model of the latch: it powers up as 0, takes the data pins on each
    // metaclock edge while load (Phi2) is high, and holds otherwise
    reg [7:0] f_value = 8'b0;
    always @(posedge metaclock) begin
        if (load) f_value <= data_in;
    end

    always @* begin
        check_db: assert (db_out == (dl_db ? f_value : 8'hff));
        check_adh: assert (adh_out == (dl_adh ? f_value : 8'hff));
        check_adl: assert (adl_out == (dl_adl ? f_value : 8'hff));
    end

    reg f_past_valid = 1'b0;
    always @(posedge metaclock) f_past_valid <= 1'b1;

    always @(posedge metaclock) begin
        if (f_past_valid) begin
            reach_load: cover ($past(load) && dl_db
                && db_out != 8'b0 && db_out != 8'hff);
            // The latch keeps the value from the end of Phi2 while the pins
            // change
            reach_hold: cover (!$past(load) && dl_adl
                && adl_out != 8'b0 && adl_out != $past(data_in));
            reach_adh_only: cover (!dl_db && dl_adh && !dl_adl && adh_out != 8'hff);
            reach_all: cover (dl_db && dl_adh && dl_adl && adh_out != 8'hff);
        end
    end
endmodule
