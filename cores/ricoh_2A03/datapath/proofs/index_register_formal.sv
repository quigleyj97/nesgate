// Properties of an index register (X, Y, and the address bus registers),
// checked on every metaclock edge. The output port goes through the same
// precharge techmap as synthesis (see techmaps/precharge_tribuf.v), so a
// disabled port reads all ones.
module index_register_formal (
    input metaclock,
    input load,
    input output_enable,
    input [7:0] data_in
);
    wire [7:0] data_out;

    index_register dut (
        .data_in(data_in),
        .load(load),
        .data_out(data_out),
        .output_enable(output_enable),
        .metaclock(metaclock)
    );

    // A model of the register: it powers up as 0, takes data_in on each
    // metaclock edge while load is high, and holds otherwise
    reg [7:0] f_value = 8'b0;
    always @(posedge metaclock) begin
        if (load) f_value <= data_in;
    end

    always @* begin
        check_output: assert (data_out == (output_enable ? f_value : 8'hff));
    end

    reg f_past_valid = 1'b0;
    always @(posedge metaclock) f_past_valid <= 1'b1;

    always @(posedge metaclock) begin
        if (f_past_valid) begin
            reach_load: cover ($past(load) && output_enable
                && data_out != 8'b0 && data_out != 8'hff);
            reach_hold: cover (!$past(load) && output_enable
                && data_out != 8'b0 && data_out != $past(data_in));
            reach_released: cover (!output_enable && f_value != 8'hff
                && f_value != 8'b0);
        end
    end
endmodule
