// Properties of the instruction register, checked on every metaclock edge. It
// takes the predecoded opcode on each edge while Phi1 and FETCH are both
// high, and holds otherwise.
module instruction_register_formal (
    input metaclock,
    input phi1,
    input fetch,
    input [7:0] predecode_in
);
    wire [7:0] instruction_out;

    instruction_register dut (
        .phi1(phi1),
        .load_opcode_FETCH(fetch),
        .predecode_in(predecode_in),
        .instruction_out(instruction_out),
        .metaclock(metaclock)
    );

    // A model of the register, which powers up as 0 (BRK)
    reg f_past_valid = 1'b0;
    reg [7:0] f_value = 8'b0;
    always @(posedge metaclock) begin
        f_past_valid <= 1'b1;
        if (phi1 && fetch) f_value <= predecode_in;
    end

    always @* begin
        check_value: assert (instruction_out == f_value);
    end

    always @(posedge metaclock) begin
        if (f_past_valid) begin
            reach_load: cover ($past(phi1) && $past(fetch) && instruction_out != 8'b0);
            // FETCH is low during Phi1: the IR keeps the current opcode
            reach_hold_no_fetch: cover ($past(phi1) && !$past(fetch)
                && instruction_out != 8'b0 && instruction_out != $past(predecode_in));
            // FETCH is still high during Phi2: the IR doesn't load
            reach_hold_phi2: cover (!$past(phi1) && $past(fetch)
                && instruction_out != 8'b0 && instruction_out != $past(predecode_in));
        end
    end
endmodule
