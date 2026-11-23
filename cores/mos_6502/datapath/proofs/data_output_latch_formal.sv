// Properties of the data output register, checked on every metaclock edge.
// Released data pins read all ones.
module data_output_latch_formal (
    input metaclock,
    input phi1,
    input phi2,
    input r_not_w,
    input [7:0] db_in
);
    wire [7:0] data_out;

    data_output_latch dut (
        .phi1(phi1),
        .phi2(phi2),
        .signal_R_NOT_W(r_not_w),
        .data_in(db_in),
        .data_out(data_out),
        .metaclock(metaclock)
    );

    // A model of the register: it powers up as 0, takes DB on each metaclock
    // edge while Phi1 is high, and holds otherwise. The pins are driven only
    // during Phi2 of a write.
    reg [7:0] f_value = 8'b0;
    always @(posedge metaclock) begin
        if (phi1) f_value <= db_in;
    end

    always @* begin
        check_pins: assert (data_out == (!r_not_w && phi2 ? f_value : 8'hff));
    end

    reg f_past_valid = 1'b0;
    always @(posedge metaclock) f_past_valid <= 1'b1;

    always @(posedge metaclock) begin
        if (f_past_valid) begin
            // Loaded during Phi1, then written out during Phi2
            reach_write: cover ($past(phi1) && !phi1 && phi2 && !r_not_w
                && data_out != 8'b0 && data_out != 8'hff);
            // DB changes during Phi2, but the pins keep the Phi1 value
            reach_hold: cover (!$past(phi1) && phi2 && !r_not_w
                && data_out != 8'b0 && data_out != $past(db_in));
            reach_read_released: cover (phi2 && r_not_w && f_value != 8'hff);
        end
    end
endmodule
