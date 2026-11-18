// Properties of the B input register, checked on every metaclock edge.
module b_input_register_formal (
    input metaclock,
    input load_not_db,
    input load_db,
    input load_adl,
    input [7:0] db_in,
    input [7:0] adl_in
);
    wire [7:0] data_out;

    b_input_register dut (
        .control_not_db_add(load_not_db),
        .control_db_add(load_db),
        .control_adl_add(load_adl),
        .data_in_db(db_in),
        .data_in_adl(adl_in),
        .data_out(data_out),
        .metaclock(metaclock)
    );

    reg f_past_valid = 1'b0;
    always @(posedge metaclock) f_past_valid <= 1'b1;

    always @* begin
        if (!f_past_valid) begin
            check_power_up: assert (data_out == 8'b0);
        end
    end

    always @(posedge metaclock) begin
        if (f_past_valid) begin
            if ($past(load_not_db)) begin
                check_load_not_db: assert (data_out == ~$past(db_in));
            end else if ($past(load_db)) begin
                check_load_db: assert (data_out == $past(db_in));
            end else if ($past(load_adl)) begin
                check_load_adl: assert (data_out == $past(adl_in));
            end else begin
                check_hold: assert (data_out == $past(data_out));
            end

            reach_load_not_db: cover ($past(load_not_db) && !$past(load_db)
                && !$past(load_adl) && data_out != 8'hff);
            reach_load_db: cover (!$past(load_not_db) && $past(load_db)
                && !$past(load_adl) && data_out != 8'b0);
            reach_load_adl: cover (!$past(load_not_db) && !$past(load_db)
                && $past(load_adl) && data_out != 8'b0);
            reach_priority: cover ($past(load_not_db) && $past(load_db)
                && $past(load_adl) && $past(db_in) != $past(adl_in));
            reach_hold: cover (!$past(load_not_db) && !$past(load_db) && !$past(load_adl)
                && data_out != 8'b0 && $past(db_in) != data_out
                && $past(adl_in) != data_out);
        end
    end
endmodule
