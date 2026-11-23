// Properties of the A input register, checked on every metaclock edge.
module a_input_register_formal (
    input metaclock,
    input load,
    input clear,
    input [7:0] data_in
);
    wire [7:0] data_out;

    a_input_register dut (
        .load_SB_ADD(load),
        .data_in_SB(data_in),
        .clear_0_ADD(clear),
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
            if ($past(load)) begin
                check_load: assert (data_out == $past(data_in));
            end else if ($past(clear)) begin
                check_clear: assert (data_out == 8'b0);
            end else begin
                check_hold: assert (data_out == $past(data_out));
            end

            reach_load: cover ($past(load) && !$past(clear) && data_out != 8'b0);
            reach_clear: cover (!$past(load) && $past(clear) && $past(data_out) != 8'b0);
            reach_load_over_clear: cover ($past(load) && $past(clear) && data_out != 8'b0);
            reach_hold: cover (!$past(load) && !$past(clear)
                && data_out != 8'b0 && $past(data_in) != data_out);
        end
    end
endmodule
