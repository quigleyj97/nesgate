// Properties of the predecode register, checked on every metaclock edge. It
// takes the data bus on each edge while Phi2 is high, and holds otherwise.
module predecode_register_formal (
    input metaclock,
    input phi2,
    input [7:0] data_in
);
    wire [7:0] predecode_out;

    predecode_register dut (
        .phi2(phi2),
        .data_in(data_in),
        .predecode_out(predecode_out),
        .metaclock(metaclock)
    );

    // A model of the register, which powers up as 0
    reg f_past_valid = 1'b0;
    reg [7:0] f_value = 8'b0;
    always @(posedge metaclock) begin
        f_past_valid <= 1'b1;
        if (phi2) f_value <= data_in;
    end

    always @* begin
        check_value: assert (predecode_out == f_value);
    end

    always @(posedge metaclock) begin
        if (f_past_valid) begin
            reach_load: cover ($past(phi2) && predecode_out != 8'b0
                && predecode_out != $past(predecode_out));
            // Phi2 is low: the bus changes, but the register holds
            reach_hold: cover (!$past(phi2) && predecode_out != 8'b0
                && predecode_out != $past(data_in));
            // Phi2 stays high: the register follows the bus
            reach_follow: cover ($past(phi2) && $past(phi2, 2)
                && predecode_out != $past(predecode_out)
                && $past(predecode_out) != $past(predecode_out, 2));
        end
    end
endmodule
