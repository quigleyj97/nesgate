// Properties of the decoder ROM, for every opcode, every combination of the
// cycle inputs (several can be set at once, as T0 and T2 are on 2-cycle
// instructions), and PRDY.
//
// Each line is checked against the opcodes it matches and the cycle it fires
// in, as decoded in the decoder table, rather than the raw transistor bits the
// VHDL uses, so the two check each other. Generated from the table in
// verify_decoder_rom.py, which uses the same decoded masks.
//
// On top of the table, line 73 (Branch T0) is gated by PRDY, and lines 83, 90
// and 128 don't fire for the push/pull instructions (line 129). Line 128 also
// needs IR0 = 0, which the table's mask for it already says.
module decoder_rom_formal (
    input [7:0] ir,
    input cycle_t0,
    input cycle_t1x,
    input cycle_t2,
    input cycle_t3,
    input cycle_t4,
    input cycle_t5,
    input prdy
);
    wire [129:0] decoder_out;

    decoder_rom dut (
        .instruction_in(ir),
        .cycle_T0(cycle_t0),
        .cycle_T1X(cycle_t1x),
        .cycle_T2(cycle_t2),
        .cycle_T3(cycle_t3),
        .cycle_T4(cycle_t4),
        .cycle_T5(cycle_t5),
        .previous_ready_PRDY(prdy),
        .decoder_out(decoder_out)
    );

    // Which lines match the opcode, and which lines' cycles are active
    reg [129:0] f_opcode;
    reg [129:0] f_cycle;
    always @* begin
        f_opcode = 130'b0;
        casez (ir) 8'b100??100: f_opcode[0] = 1'b1; default: ; endcase // STY
        casez (ir) 8'b???100?1: f_opcode[1] = 1'b1; default: ; endcase // OP ind, Y
        casez (ir) 8'b???110?1: f_opcode[2] = 1'b1; default: ; endcase // OP abs, Y
        casez (ir) 8'b1?001000: f_opcode[3] = 1'b1; default: ; endcase // DEY INY
        casez (ir) 8'b10011000: f_opcode[4] = 1'b1; default: ; endcase // TYA
        casez (ir) 8'b1100??00: f_opcode[5] = 1'b1; default: ; endcase // CPY INY
        casez (ir) 8'b???1?1??: f_opcode[6] = 1'b1; default: ; endcase // OP zpg, X/Y & OP abs, X/Y
        casez (ir) 8'b10????1?: f_opcode[7] = 1'b1; default: ; endcase // LDX STX A>X S>X
        casez (ir) 8'b???000?1: f_opcode[8] = 1'b1; default: ; endcase // OP ind, X
        casez (ir) 8'b1000101?: f_opcode[9] = 1'b1; default: ; endcase // TXA
        casez (ir) 8'b1100101?: f_opcode[10] = 1'b1; default: ; endcase // DEX
        casez (ir) 8'b1110??00: f_opcode[11] = 1'b1; default: ; endcase // CPX INX
        casez (ir) 8'b100???1?: f_opcode[12] = 1'b1; default: ; endcase // STX TXA TXS
        casez (ir) 8'b1001101?: f_opcode[13] = 1'b1; default: ; endcase // TXS
        casez (ir) 8'b101???1?: f_opcode[14] = 1'b1; default: ; endcase // LDX TAX TSX
        casez (ir) 8'b1100101?: f_opcode[15] = 1'b1; default: ; endcase // DEX
        casez (ir) 8'b11101000: f_opcode[16] = 1'b1; default: ; endcase // INX
        casez (ir) 8'b1011101?: f_opcode[17] = 1'b1; default: ; endcase // TSX
        casez (ir) 8'b1?001000: f_opcode[18] = 1'b1; default: ; endcase // DEY INY
        casez (ir) 8'b101??100: f_opcode[19] = 1'b1; default: ; endcase // LDY
        casez (ir) 8'b1010??00: f_opcode[20] = 1'b1; default: ; endcase // LDY TAY
        casez (ir) 8'b00100000: f_opcode[21] = 1'b1; default: ; endcase // JSR
        casez (ir) 8'b00000000: f_opcode[22] = 1'b1; default: ; endcase // BRK
        casez (ir) 8'b0?001000: f_opcode[23] = 1'b1; default: ; endcase // Push
        casez (ir) 8'b01100000: f_opcode[24] = 1'b1; default: ; endcase // RTS
        casez (ir) 8'b0?101000: f_opcode[25] = 1'b1; default: ; endcase // Pull
        casez (ir) 8'b01000000: f_opcode[26] = 1'b1; default: ; endcase // RTI
        casez (ir) 8'b011???1?: f_opcode[27] = 1'b1; default: ; endcase // ROR
        casez (ir) 8'b????????: f_opcode[28] = 1'b1; default: ; endcase // T2 ANY
        casez (ir) 8'b010????1: f_opcode[29] = 1'b1; default: ; endcase // EOR
        casez (ir) 8'b01?01100: f_opcode[30] = 1'b1; default: ; endcase // JMP (excluder for C11)
        casez (ir) 8'b???011??: f_opcode[31] = 1'b1; default: ; endcase // ALU absolute
        casez (ir) 8'b000????1: f_opcode[32] = 1'b1; default: ; endcase // ORA
        casez (ir) 8'b????0???: f_opcode[33] = 1'b1; default: ; endcase // Left half (X0-X7)
        casez (ir) 8'b????????: f_opcode[34] = 1'b1; default: ; endcase // T0 ANY
        casez (ir) 8'b0??0?000: f_opcode[35] = 1'b1; default: ; endcase // BRK JSR RTI RTS Push/pull
        casez (ir) 8'b0??0??00: f_opcode[36] = 1'b1; default: ; endcase // BRK JSR RTI RTS Push/pull BIT JMP
        casez (ir) 8'b00?00000: f_opcode[37] = 1'b1; default: ; endcase // BRK JSR
        casez (ir) 8'b01000000: f_opcode[38] = 1'b1; default: ; endcase // RTI
        casez (ir) 8'b???000?1: f_opcode[39] = 1'b1; default: ; endcase // OP X, ind
        casez (ir) 8'b???100?1: f_opcode[40] = 1'b1; default: ; endcase // OP ind, Y
        casez (ir) 8'b???100?1: f_opcode[41] = 1'b1; default: ; endcase // OP ind, Y
        casez (ir) 8'b???11???: f_opcode[42] = 1'b1; default: ; endcase // RIGHT ODD
        casez (ir) 8'b0?101000: f_opcode[43] = 1'b1; default: ; endcase // Pull
        casez (ir) 8'b111???1?: f_opcode[44] = 1'b1; default: ; endcase // INC NOP
        casez (ir) 8'b???000?1: f_opcode[45] = 1'b1; default: ; endcase // OP X, ind
        casez (ir) 8'b???100?1: f_opcode[46] = 1'b1; default: ; endcase // OP ind, Y
        casez (ir) 8'b01?00000: f_opcode[47] = 1'b1; default: ; endcase // RTI RTS
        casez (ir) 8'b00100000: f_opcode[48] = 1'b1; default: ; endcase // JSR
        casez (ir) 8'b11?0??00: f_opcode[49] = 1'b1; default: ; endcase // CPY CPX INY INX
        casez (ir) 8'b110????1: f_opcode[50] = 1'b1; default: ; endcase // CMP
        casez (ir) 8'b111????1: f_opcode[51] = 1'b1; default: ; endcase // SBC
        casez (ir) 8'b?11????1: f_opcode[52] = 1'b1; default: ; endcase // ADC SBC
        casez (ir) 8'b001???1?: f_opcode[53] = 1'b1; default: ; endcase // ROL
        casez (ir) 8'b01?01100: f_opcode[54] = 1'b1; default: ; endcase // JMP ind
        casez (ir) 8'b00????1?: f_opcode[55] = 1'b1; default: ; endcase // ASL ROL
        casez (ir) 8'b00100000: f_opcode[56] = 1'b1; default: ; endcase // JSR
        casez (ir) 8'b0??0?000: f_opcode[57] = 1'b1; default: ; endcase // BRK JSR RTI RTS Push/pull
        casez (ir) 8'b10011000: f_opcode[58] = 1'b1; default: ; endcase // TYA
        casez (ir) 8'b0??????1: f_opcode[59] = 1'b1; default: ; endcase // UPPER ODD
        casez (ir) 8'b?11????1: f_opcode[60] = 1'b1; default: ; endcase // ADC SBC
        casez (ir) 8'b0??0101?: f_opcode[61] = 1'b1; default: ; endcase // ASL ROL LSR ROR
        casez (ir) 8'b1000101?: f_opcode[62] = 1'b1; default: ; endcase // TXA
        casez (ir) 8'b01101000: f_opcode[63] = 1'b1; default: ; endcase // PLA
        casez (ir) 8'b101????1: f_opcode[64] = 1'b1; default: ; endcase // LDA
        casez (ir) 8'b???????1: f_opcode[65] = 1'b1; default: ; endcase // ALL ODD
        casez (ir) 8'b10101000: f_opcode[66] = 1'b1; default: ; endcase // TAY
        casez (ir) 8'b0??0101?: f_opcode[67] = 1'b1; default: ; endcase // ASL ROL LSR ROR
        casez (ir) 8'b1010101?: f_opcode[68] = 1'b1; default: ; endcase // TAX
        casez (ir) 8'b0010?100: f_opcode[69] = 1'b1; default: ; endcase // BIT0
        casez (ir) 8'b001????1: f_opcode[70] = 1'b1; default: ; endcase // AND0
        casez (ir) 8'b???11???: f_opcode[71] = 1'b1; default: ; endcase // OP abs,XY
        casez (ir) 8'b???100?1: f_opcode[72] = 1'b1; default: ; endcase // OP ind,Y
        casez (ir) 8'b???10000: f_opcode[73] = 1'b1; default: ; endcase // Branch T0
        casez (ir) 8'b01001000: f_opcode[74] = 1'b1; default: ; endcase // PHA
        casez (ir) 8'b01?0101?: f_opcode[75] = 1'b1; default: ; endcase // LSR ROR
        casez (ir) 8'b01????1?: f_opcode[76] = 1'b1; default: ; endcase // LSR ROR
        casez (ir) 8'b00000000: f_opcode[77] = 1'b1; default: ; endcase // BRK
        casez (ir) 8'b00100000: f_opcode[78] = 1'b1; default: ; endcase // JSR
        casez (ir) 8'b100????1: f_opcode[79] = 1'b1; default: ; endcase // STA
        casez (ir) 8'b???10000: f_opcode[80] = 1'b1; default: ; endcase // BR2 (Branch T2)
        casez (ir) 8'b????01??: f_opcode[81] = 1'b1; default: ; endcase // zero page
        casez (ir) 8'b????00?1: f_opcode[82] = 1'b1; default: ; endcase // ALU indirect
        casez (ir) 8'b????1???: f_opcode[83] = 1'b1; default: ; endcase // Right half (X8-XF)
        casez (ir) 8'b01100000: f_opcode[84] = 1'b1; default: ; endcase // RTS
        casez (ir) 8'b????????: f_opcode[85] = 1'b1; default: ; endcase // T4 ANY
        casez (ir) 8'b????????: f_opcode[86] = 1'b1; default: ; endcase // T3 ANY
        casez (ir) 8'b0?000000: f_opcode[87] = 1'b1; default: ; endcase // BRK RTI
        casez (ir) 8'b01?01100: f_opcode[88] = 1'b1; default: ; endcase // JMP
        casez (ir) 8'b???000?1: f_opcode[89] = 1'b1; default: ; endcase // OP X, ind
        casez (ir) 8'b????1???: f_opcode[90] = 1'b1; default: ; endcase // Right half (X8-XF)
        casez (ir) 8'b???100?1: f_opcode[91] = 1'b1; default: ; endcase // OP ind, Y
        casez (ir) 8'b???11???: f_opcode[92] = 1'b1; default: ; endcase // RIGHT ODD
        casez (ir) 8'b???10000: f_opcode[93] = 1'b1; default: ; endcase // BR3 (Branch T3)
        casez (ir) 8'b0?000000: f_opcode[94] = 1'b1; default: ; endcase // BRK RTI
        casez (ir) 8'b00100000: f_opcode[95] = 1'b1; default: ; endcase // JSR
        casez (ir) 8'b01?01100: f_opcode[96] = 1'b1; default: ; endcase // JMP
        casez (ir) 8'b100?????: f_opcode[97] = 1'b1; default: ; endcase // STORE
        casez (ir) 8'b00000000: f_opcode[98] = 1'b1; default: ; endcase // BRK
        casez (ir) 8'b00001000: f_opcode[99] = 1'b1; default: ; endcase // PHP
        casez (ir) 8'b0?001000: f_opcode[100] = 1'b1; default: ; endcase // Push
        casez (ir) 8'b01?01100: f_opcode[101] = 1'b1; default: ; endcase // JMP ind
        casez (ir) 8'b01?00000: f_opcode[102] = 1'b1; default: ; endcase // RTI RTS
        casez (ir) 8'b00100000: f_opcode[103] = 1'b1; default: ; endcase // JSR
        casez (ir) 8'b01001100: f_opcode[104] = 1'b1; default: ; endcase // JMP abs
        casez (ir) 8'b0?101000: f_opcode[105] = 1'b1; default: ; endcase // Pull
        casez (ir) 8'b?1????1?: f_opcode[106] = 1'b1; default: ; endcase // LSR ROR DEC INC DEX NOP
        casez (ir) 8'b00????1?: f_opcode[107] = 1'b1; default: ; endcase // ASL ROL
        casez (ir) 8'b01?11000: f_opcode[108] = 1'b1; default: ; endcase // CLI SEI
        casez (ir) 8'b0010?100: f_opcode[109] = 1'b1; default: ; endcase // BIT
        casez (ir) 8'b00?11000: f_opcode[110] = 1'b1; default: ; endcase // CLC SEC
        casez (ir) 8'b???101??: f_opcode[111] = 1'b1; default: ; endcase // Memory zero page X/Y
        casez (ir) 8'b?11????1: f_opcode[112] = 1'b1; default: ; endcase // ADC SBC
        casez (ir) 8'b0010?100: f_opcode[113] = 1'b1; default: ; endcase // BIT
        casez (ir) 8'b00101000: f_opcode[114] = 1'b1; default: ; endcase // PLP
        casez (ir) 8'b01000000: f_opcode[115] = 1'b1; default: ; endcase // RTI
        casez (ir) 8'b110????1: f_opcode[116] = 1'b1; default: ; endcase // CMP
        casez (ir) 8'b11?01100: f_opcode[117] = 1'b1; default: ; endcase // CPY CPX abs
        casez (ir) 8'b00?0101?: f_opcode[118] = 1'b1; default: ; endcase // ASL ROL
        casez (ir) 8'b11?00?00: f_opcode[119] = 1'b1; default: ; endcase // CPY CPX zpg/immed
        casez (ir) 8'b11?11000: f_opcode[120] = 1'b1; default: ; endcase // CLD SED
        casez (ir) 8'b?0??????: f_opcode[121] = 1'b1; default: ; endcase // /IR6
        casez (ir) 8'b???011??: f_opcode[122] = 1'b1; default: ; endcase // Memory absolute
        casez (ir) 8'b???001??: f_opcode[123] = 1'b1; default: ; endcase // Memory zero page
        casez (ir) 8'b????00?1: f_opcode[124] = 1'b1; default: ; endcase // Memory indirect
        casez (ir) 8'b???11???: f_opcode[125] = 1'b1; default: ; endcase // Memory absolute X/Y
        casez (ir) 8'b0???????: f_opcode[126] = 1'b1; default: ; endcase // /IR7
        casez (ir) 8'b10111000: f_opcode[127] = 1'b1; default: ; endcase // CLV
        casez (ir) 8'b????10?0: f_opcode[128] = 1'b1; default: ; endcase // IMPL
        casez (ir) 8'b0??01000: f_opcode[129] = 1'b1; default: ; endcase // Push/pull

        f_cycle[0] = 1'b1;
        f_cycle[1] = cycle_t3;
        f_cycle[2] = cycle_t2;
        f_cycle[3] = cycle_t0;
        f_cycle[4] = cycle_t0;
        f_cycle[5] = cycle_t0;
        f_cycle[6] = cycle_t2;
        f_cycle[7] = 1'b1;
        f_cycle[8] = cycle_t2;
        f_cycle[9] = cycle_t0;
        f_cycle[10] = cycle_t0;
        f_cycle[11] = cycle_t0;
        f_cycle[12] = 1'b1;
        f_cycle[13] = cycle_t0;
        f_cycle[14] = cycle_t0;
        f_cycle[15] = cycle_t1x;
        f_cycle[16] = cycle_t1x;
        f_cycle[17] = cycle_t0;
        f_cycle[18] = cycle_t1x;
        f_cycle[19] = cycle_t0;
        f_cycle[20] = cycle_t0;
        f_cycle[21] = cycle_t0;
        f_cycle[22] = cycle_t5;
        f_cycle[23] = cycle_t0;
        f_cycle[24] = cycle_t4;
        f_cycle[25] = cycle_t3;
        f_cycle[26] = cycle_t5;
        f_cycle[27] = 1'b1;
        f_cycle[28] = cycle_t2;
        f_cycle[29] = cycle_t0;
        f_cycle[30] = 1'b1;
        f_cycle[31] = cycle_t2;
        f_cycle[32] = cycle_t0;
        f_cycle[33] = cycle_t2;
        f_cycle[34] = cycle_t0;
        f_cycle[35] = cycle_t2;
        f_cycle[36] = cycle_t3;
        f_cycle[37] = cycle_t4;
        f_cycle[38] = cycle_t4;
        f_cycle[39] = cycle_t3;
        f_cycle[40] = cycle_t4;
        f_cycle[41] = cycle_t2;
        f_cycle[42] = cycle_t3;
        f_cycle[43] = 1'b1;
        f_cycle[44] = 1'b1;
        f_cycle[45] = cycle_t4;
        f_cycle[46] = cycle_t3;
        f_cycle[47] = 1'b1;
        f_cycle[48] = cycle_t2;
        f_cycle[49] = cycle_t0;
        f_cycle[50] = cycle_t0;
        f_cycle[51] = cycle_t0;
        f_cycle[52] = cycle_t0;
        f_cycle[53] = 1'b1;
        f_cycle[54] = cycle_t3;
        f_cycle[55] = 1'b1;
        f_cycle[56] = cycle_t5;
        f_cycle[57] = cycle_t2;
        f_cycle[58] = cycle_t0;
        f_cycle[59] = cycle_t1x;
        f_cycle[60] = cycle_t1x;
        f_cycle[61] = cycle_t1x;
        f_cycle[62] = cycle_t0;
        f_cycle[63] = cycle_t0;
        f_cycle[64] = cycle_t0;
        f_cycle[65] = cycle_t0;
        f_cycle[66] = cycle_t0;
        f_cycle[67] = cycle_t0;
        f_cycle[68] = cycle_t0;
        f_cycle[69] = cycle_t0;
        f_cycle[70] = cycle_t0;
        f_cycle[71] = cycle_t4;
        f_cycle[72] = cycle_t5;
        f_cycle[73] = cycle_t0;
        f_cycle[74] = cycle_t2;
        f_cycle[75] = cycle_t0;
        f_cycle[76] = 1'b1;
        f_cycle[77] = cycle_t2;
        f_cycle[78] = cycle_t3;
        f_cycle[79] = 1'b1;
        f_cycle[80] = cycle_t2;
        f_cycle[81] = cycle_t2;
        f_cycle[82] = cycle_t2;
        f_cycle[83] = cycle_t2;
        f_cycle[84] = cycle_t5;
        f_cycle[85] = cycle_t4;
        f_cycle[86] = cycle_t3;
        f_cycle[87] = cycle_t0;
        f_cycle[88] = cycle_t0;
        f_cycle[89] = cycle_t5;
        f_cycle[90] = cycle_t3;
        f_cycle[91] = cycle_t4;
        f_cycle[92] = cycle_t3;
        f_cycle[93] = cycle_t3;
        f_cycle[94] = 1'b1;
        f_cycle[95] = 1'b1;
        f_cycle[96] = 1'b1;
        f_cycle[97] = 1'b1;
        f_cycle[98] = cycle_t4;
        f_cycle[99] = cycle_t2;
        f_cycle[100] = cycle_t2;
        f_cycle[101] = cycle_t4;
        f_cycle[102] = cycle_t5;
        f_cycle[103] = cycle_t5;
        f_cycle[104] = cycle_t2;
        f_cycle[105] = cycle_t3;
        f_cycle[106] = 1'b1;
        f_cycle[107] = 1'b1;
        f_cycle[108] = cycle_t0;
        f_cycle[109] = cycle_t1x;
        f_cycle[110] = cycle_t0;
        f_cycle[111] = cycle_t3;
        f_cycle[112] = cycle_t1x;
        f_cycle[113] = cycle_t0;
        f_cycle[114] = cycle_t0;
        f_cycle[115] = cycle_t4;
        f_cycle[116] = cycle_t1x;
        f_cycle[117] = cycle_t1x;
        f_cycle[118] = cycle_t1x;
        f_cycle[119] = cycle_t1x;
        f_cycle[120] = cycle_t0;
        f_cycle[121] = 1'b1;
        f_cycle[122] = cycle_t3;
        f_cycle[123] = cycle_t2;
        f_cycle[124] = cycle_t5;
        f_cycle[125] = cycle_t4;
        f_cycle[126] = 1'b1;
        f_cycle[127] = 1'b1;
        f_cycle[128] = 1'b1;
        f_cycle[129] = 1'b1;
    end

    wire f_push_pull = f_opcode[129];
    reg [129:0] f_lines;
    always @* begin
        f_lines = f_opcode & f_cycle;
        f_lines[73] = f_lines[73] && prdy;
        f_lines[83] = f_lines[83] && !f_push_pull;
        f_lines[90] = f_lines[90] && !f_push_pull;
        f_lines[128] = f_lines[128] && !f_push_pull;
    end

    // One assertion per line, so a failure names the line
    always @* begin
        check_line_0: assert (decoder_out[0] == f_lines[0]);
        check_line_1: assert (decoder_out[1] == f_lines[1]);
        check_line_2: assert (decoder_out[2] == f_lines[2]);
        check_line_3: assert (decoder_out[3] == f_lines[3]);
        check_line_4: assert (decoder_out[4] == f_lines[4]);
        check_line_5: assert (decoder_out[5] == f_lines[5]);
        check_line_6: assert (decoder_out[6] == f_lines[6]);
        check_line_7: assert (decoder_out[7] == f_lines[7]);
        check_line_8: assert (decoder_out[8] == f_lines[8]);
        check_line_9: assert (decoder_out[9] == f_lines[9]);
        check_line_10: assert (decoder_out[10] == f_lines[10]);
        check_line_11: assert (decoder_out[11] == f_lines[11]);
        check_line_12: assert (decoder_out[12] == f_lines[12]);
        check_line_13: assert (decoder_out[13] == f_lines[13]);
        check_line_14: assert (decoder_out[14] == f_lines[14]);
        check_line_15: assert (decoder_out[15] == f_lines[15]);
        check_line_16: assert (decoder_out[16] == f_lines[16]);
        check_line_17: assert (decoder_out[17] == f_lines[17]);
        check_line_18: assert (decoder_out[18] == f_lines[18]);
        check_line_19: assert (decoder_out[19] == f_lines[19]);
        check_line_20: assert (decoder_out[20] == f_lines[20]);
        check_line_21: assert (decoder_out[21] == f_lines[21]);
        check_line_22: assert (decoder_out[22] == f_lines[22]);
        check_line_23: assert (decoder_out[23] == f_lines[23]);
        check_line_24: assert (decoder_out[24] == f_lines[24]);
        check_line_25: assert (decoder_out[25] == f_lines[25]);
        check_line_26: assert (decoder_out[26] == f_lines[26]);
        check_line_27: assert (decoder_out[27] == f_lines[27]);
        check_line_28: assert (decoder_out[28] == f_lines[28]);
        check_line_29: assert (decoder_out[29] == f_lines[29]);
        check_line_30: assert (decoder_out[30] == f_lines[30]);
        check_line_31: assert (decoder_out[31] == f_lines[31]);
        check_line_32: assert (decoder_out[32] == f_lines[32]);
        check_line_33: assert (decoder_out[33] == f_lines[33]);
        check_line_34: assert (decoder_out[34] == f_lines[34]);
        check_line_35: assert (decoder_out[35] == f_lines[35]);
        check_line_36: assert (decoder_out[36] == f_lines[36]);
        check_line_37: assert (decoder_out[37] == f_lines[37]);
        check_line_38: assert (decoder_out[38] == f_lines[38]);
        check_line_39: assert (decoder_out[39] == f_lines[39]);
        check_line_40: assert (decoder_out[40] == f_lines[40]);
        check_line_41: assert (decoder_out[41] == f_lines[41]);
        check_line_42: assert (decoder_out[42] == f_lines[42]);
        check_line_43: assert (decoder_out[43] == f_lines[43]);
        check_line_44: assert (decoder_out[44] == f_lines[44]);
        check_line_45: assert (decoder_out[45] == f_lines[45]);
        check_line_46: assert (decoder_out[46] == f_lines[46]);
        check_line_47: assert (decoder_out[47] == f_lines[47]);
        check_line_48: assert (decoder_out[48] == f_lines[48]);
        check_line_49: assert (decoder_out[49] == f_lines[49]);
        check_line_50: assert (decoder_out[50] == f_lines[50]);
        check_line_51: assert (decoder_out[51] == f_lines[51]);
        check_line_52: assert (decoder_out[52] == f_lines[52]);
        check_line_53: assert (decoder_out[53] == f_lines[53]);
        check_line_54: assert (decoder_out[54] == f_lines[54]);
        check_line_55: assert (decoder_out[55] == f_lines[55]);
        check_line_56: assert (decoder_out[56] == f_lines[56]);
        check_line_57: assert (decoder_out[57] == f_lines[57]);
        check_line_58: assert (decoder_out[58] == f_lines[58]);
        check_line_59: assert (decoder_out[59] == f_lines[59]);
        check_line_60: assert (decoder_out[60] == f_lines[60]);
        check_line_61: assert (decoder_out[61] == f_lines[61]);
        check_line_62: assert (decoder_out[62] == f_lines[62]);
        check_line_63: assert (decoder_out[63] == f_lines[63]);
        check_line_64: assert (decoder_out[64] == f_lines[64]);
        check_line_65: assert (decoder_out[65] == f_lines[65]);
        check_line_66: assert (decoder_out[66] == f_lines[66]);
        check_line_67: assert (decoder_out[67] == f_lines[67]);
        check_line_68: assert (decoder_out[68] == f_lines[68]);
        check_line_69: assert (decoder_out[69] == f_lines[69]);
        check_line_70: assert (decoder_out[70] == f_lines[70]);
        check_line_71: assert (decoder_out[71] == f_lines[71]);
        check_line_72: assert (decoder_out[72] == f_lines[72]);
        check_line_73: assert (decoder_out[73] == f_lines[73]);
        check_line_74: assert (decoder_out[74] == f_lines[74]);
        check_line_75: assert (decoder_out[75] == f_lines[75]);
        check_line_76: assert (decoder_out[76] == f_lines[76]);
        check_line_77: assert (decoder_out[77] == f_lines[77]);
        check_line_78: assert (decoder_out[78] == f_lines[78]);
        check_line_79: assert (decoder_out[79] == f_lines[79]);
        check_line_80: assert (decoder_out[80] == f_lines[80]);
        check_line_81: assert (decoder_out[81] == f_lines[81]);
        check_line_82: assert (decoder_out[82] == f_lines[82]);
        check_line_83: assert (decoder_out[83] == f_lines[83]);
        check_line_84: assert (decoder_out[84] == f_lines[84]);
        check_line_85: assert (decoder_out[85] == f_lines[85]);
        check_line_86: assert (decoder_out[86] == f_lines[86]);
        check_line_87: assert (decoder_out[87] == f_lines[87]);
        check_line_88: assert (decoder_out[88] == f_lines[88]);
        check_line_89: assert (decoder_out[89] == f_lines[89]);
        check_line_90: assert (decoder_out[90] == f_lines[90]);
        check_line_91: assert (decoder_out[91] == f_lines[91]);
        check_line_92: assert (decoder_out[92] == f_lines[92]);
        check_line_93: assert (decoder_out[93] == f_lines[93]);
        check_line_94: assert (decoder_out[94] == f_lines[94]);
        check_line_95: assert (decoder_out[95] == f_lines[95]);
        check_line_96: assert (decoder_out[96] == f_lines[96]);
        check_line_97: assert (decoder_out[97] == f_lines[97]);
        check_line_98: assert (decoder_out[98] == f_lines[98]);
        check_line_99: assert (decoder_out[99] == f_lines[99]);
        check_line_100: assert (decoder_out[100] == f_lines[100]);
        check_line_101: assert (decoder_out[101] == f_lines[101]);
        check_line_102: assert (decoder_out[102] == f_lines[102]);
        check_line_103: assert (decoder_out[103] == f_lines[103]);
        check_line_104: assert (decoder_out[104] == f_lines[104]);
        check_line_105: assert (decoder_out[105] == f_lines[105]);
        check_line_106: assert (decoder_out[106] == f_lines[106]);
        check_line_107: assert (decoder_out[107] == f_lines[107]);
        check_line_108: assert (decoder_out[108] == f_lines[108]);
        check_line_109: assert (decoder_out[109] == f_lines[109]);
        check_line_110: assert (decoder_out[110] == f_lines[110]);
        check_line_111: assert (decoder_out[111] == f_lines[111]);
        check_line_112: assert (decoder_out[112] == f_lines[112]);
        check_line_113: assert (decoder_out[113] == f_lines[113]);
        check_line_114: assert (decoder_out[114] == f_lines[114]);
        check_line_115: assert (decoder_out[115] == f_lines[115]);
        check_line_116: assert (decoder_out[116] == f_lines[116]);
        check_line_117: assert (decoder_out[117] == f_lines[117]);
        check_line_118: assert (decoder_out[118] == f_lines[118]);
        check_line_119: assert (decoder_out[119] == f_lines[119]);
        check_line_120: assert (decoder_out[120] == f_lines[120]);
        check_line_121: assert (decoder_out[121] == f_lines[121]);
        check_line_122: assert (decoder_out[122] == f_lines[122]);
        check_line_123: assert (decoder_out[123] == f_lines[123]);
        check_line_124: assert (decoder_out[124] == f_lines[124]);
        check_line_125: assert (decoder_out[125] == f_lines[125]);
        check_line_126: assert (decoder_out[126] == f_lines[126]);
        check_line_127: assert (decoder_out[127] == f_lines[127]);
        check_line_128: assert (decoder_out[128] == f_lines[128]);
        check_line_129: assert (decoder_out[129] == f_lines[129]);
    end

    always @* begin
        // LDA # at T0: T0 ANY, LDA, ALL ODD
        reach_lda_immediate: cover (ir == 8'hA9 && cycle_t0 && decoder_out[34]
            && decoder_out[64] && decoder_out[65]);
        // A 2-cycle instruction's T0 and T2 lines at once
        reach_overlap: cover (cycle_t0 && cycle_t2 && decoder_out[34] && decoder_out[28]);
        reach_branch_not_ready: cover (ir == 8'hD0 && cycle_t0 && !prdy && !decoder_out[73]);
        reach_push_excluded: cover (ir == 8'h48 && cycle_t2 && decoder_out[129]
            && !decoder_out[83]);
        reach_impl: cover (ir == 8'hEA && decoder_out[128]);
        reach_no_line: cover (decoder_out == 130'b0);
    end
endmodule
