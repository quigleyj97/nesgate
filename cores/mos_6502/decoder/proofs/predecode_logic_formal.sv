// Properties of the predecode logic, for every opcode, with and without 0/IR.
//
// TWOCYCLE is checked against an explicit list of the opcodes that finish in
// 2 cycles (branches aside, which end at BR2 instead), rather than the bit
// patterns the logic uses, so the two check each other. IMPLIED is set for
// the single-byte opcodes in columns 8 and A of the opcode matrix.
module predecode_logic_formal (
    input [7:0] predecode_in,
    input inject_brk
);
    wire [7:0] predecode_out;
    wire twocycle;
    wire implied;

    predecode_logic dut (
        .predecode_in(predecode_in),
        .inject_brk_0_IR(inject_brk),
        .predecode_out(predecode_out),
        .short_instruction_TWOCYCLE(twocycle),
        .single_byte_IMPLIED(implied)
    );

    // The opcodes that finish in 2 cycles, unofficial ones included. This is a
    // bit table rather than a case statement, which Yosys would turn into a
    // ROM whose contents induction leaves unconstrained.
    function automatic spec_twocycle(input [7:0] opcode);
        reg [255:0] listed;
        begin
            listed = 256'b0;
            // Immediate ALU: ORA AND EOR ADC NOP LDA CMP SBC #
            listed['h09] = 1'b1; listed['h29] = 1'b1; listed['h49] = 1'b1; listed['h69] = 1'b1;
            listed['h89] = 1'b1; listed['hA9] = 1'b1; listed['hC9] = 1'b1; listed['hE9] = 1'b1;
            // Unofficial immediate: ANC ANC ALR ARR XAA LAX AXS SBC #
            listed['h0B] = 1'b1; listed['h2B] = 1'b1; listed['h4B] = 1'b1; listed['h6B] = 1'b1;
            listed['h8B] = 1'b1; listed['hAB] = 1'b1; listed['hCB] = 1'b1; listed['hEB] = 1'b1;
            // Immediate index: NOP LDY CPY CPX #, NOP LDX NOP NOP #
            listed['h80] = 1'b1; listed['hA0] = 1'b1; listed['hC0] = 1'b1; listed['hE0] = 1'b1;
            listed['h82] = 1'b1; listed['hA2] = 1'b1; listed['hC2] = 1'b1; listed['hE2] = 1'b1;
            // Column 8, except PHP PLP PHA PLA
            listed['h18] = 1'b1; listed['h38] = 1'b1; listed['h58] = 1'b1; listed['h78] = 1'b1;
            listed['h88] = 1'b1; listed['h98] = 1'b1; listed['hA8] = 1'b1; listed['hB8] = 1'b1;
            listed['hC8] = 1'b1; listed['hD8] = 1'b1; listed['hE8] = 1'b1; listed['hF8] = 1'b1;
            // Column A: the accumulator shifts, transfers, DEX and NOPs
            listed['h0A] = 1'b1; listed['h1A] = 1'b1; listed['h2A] = 1'b1; listed['h3A] = 1'b1;
            listed['h4A] = 1'b1; listed['h5A] = 1'b1; listed['h6A] = 1'b1; listed['h7A] = 1'b1;
            listed['h8A] = 1'b1; listed['h9A] = 1'b1; listed['hAA] = 1'b1; listed['hBA] = 1'b1;
            listed['hCA] = 1'b1; listed['hDA] = 1'b1; listed['hEA] = 1'b1; listed['hFA] = 1'b1;
            spec_twocycle = listed[opcode];
        end
    endfunction

    wire [7:0] f_opcode = inject_brk ? 8'h00 : predecode_in;

    always @* begin
        check_opcode: assert (predecode_out == f_opcode);
        check_twocycle: assert (twocycle == spec_twocycle(f_opcode));
        check_implied: assert (implied
            == (f_opcode[3:0] == 4'h8 || f_opcode[3:0] == 4'hA));

        reach_brk_injected: cover (inject_brk && predecode_in == 8'hEA);
        reach_twocycle_implied: cover (twocycle && implied);
        reach_twocycle_immediate: cover (twocycle && !implied);
        reach_implied_stack: cover (!twocycle && implied);
    end
endmodule
