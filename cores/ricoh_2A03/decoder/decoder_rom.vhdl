library ieee;
use ieee.std_logic_1164.all;

--! @file
--! @brief Instruction decoder ROM for the Ricoh 2A03
--! @details A 21-to-130 demultiplexer (sometimes called the PLA) that decodes
--! the opcode in the @ref instruction_register and the current cycle from the
--! @ref timing_generator into 130 decoder lines for the random logic.
--!
--! On the real chip, each line is a precharged NOR gate on some of the 21 input
--! lines. In layout order, they are `/T1X`, `/T0`, both polarities of `IR5`,
--! `IR6`, `IR2`, `IR3`, `IR4` and `IR7`, then `/IR0`, `IR01` (`IR0` or `IR1`),
--! `/IR1`, and `/T2`-`/T5`. A transistor on an
--! input pulls the line low while that input is high, so each line is the AND
--! of the conditions its transistors check for. For example, a transistor on
--! `IR3` means the line needs `IR3` = 0, and one on `/T0` means it only fires
--! during @ref Ricoh_2A03_Signal_T0. A transistor on `IR01` needs both `IR0`
--! and `IR1` to be 0.
--!
--! `decoder_masks` holds which transistors each line has, as the "raw bits"
--! from the decoder table, in the input order above. Each line's comment gives 
--! its group and number in the decoder table, the opcodes it matches (`X` for
--! don't care), and the cycle it fires in (`TX` for any).
--!
--! Some lines have extra logic, which is part of the random logic but sits in
--! the decoder area. This entity includes it, so those lines come out already
--! modified:
--!
--! - Line 129 matches the stack push/pull instructions (`0XX01000`). It is
--!   only used to exclude them from lines 83, 90 and 128.
--! - Line 73 (Branch T0) is also gated by @ref Ricoh_2A03_Signal_PRDY, so it
--!   only fires if the CPU was ready on the previous cycle. Outside the
--!   decoder it is called `BR0`.
--! - Line 128 (IMPL) is also the only line that checks `IR0` on its own, for
--!   `XXXX10X0`.
--!
--! The real chip takes the cycle signals active-low and outputs active-low
--! lines. This core uses active-high inputs and outputs. The precharge has no
--! equivalent here, since the lines are plain combinational logic.

--! Instruction decoder ROM, decoding the opcode and cycle into 130 decoder lines
entity decoder_rom is
    port(
        --! The current opcode (IR0-IR7), from @ref instruction_register
        instruction_in: in std_ulogic_vector(7 downto 0);
        --! @ref Ricoh_2A03_Signal_T0
        cycle_T0: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_T1X
        cycle_T1X: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_T2
        cycle_T2: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_T3
        cycle_T3: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_T4
        cycle_T4: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_T5
        cycle_T5: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_PRDY
        previous_ready_PRDY: in std_ulogic;
        --! The @ref Ricoh_2A03_Decoder_Lines "decoder lines", numbered as in
        --! the decoder table
        decoder_out: out std_ulogic_vector(129 downto 0)
    );
end entity decoder_rom;

architecture rtl of decoder_rom is
    --! One decoder line's transistors, in the order of `decoder_inputs`
    subtype decoder_mask is std_ulogic_vector(0 to 20);
    type decoder_mask_array is array(0 to 129) of decoder_mask;

    --! The transistors on each decoder line, from the decoder table
    constant decoder_masks: decoder_mask_array := (
        "000101100000100100000", --   0 A01  100XX100 TX  STY
        "000000010110001000100", --   1 A02  XXX100X1 T3  OP ind, Y
        "000000011010001001000", --   2 A03  XXX110X1 T2  OP abs, Y
        "010100011001100100000", --   3 A04  1X001000 T0  DEY INY
        "010101011010100100000", --   4 A05  10011000 T0  TYA
        "010110000001100100000", --   5 A06  1100XX00 T0  CPY INY
        "000000100010000001000", --   6 B01  XXX1X1XX T2  OP zpg, X/Y & OP abs, X/Y
        "000001000000100010000", --   7 B02  10XXXX1X TX  LDX STX A>X S>X
        "000000010101001001000", --   8 B03  XXX000X1 T2  OP ind, X
        "010101011001100010000", --   9 B04  1000101X T0  TXA
        "010110011001100010000", --  10 B05  1100101X T0  DEX
        "011010000001100100000", --  11 B06  1110XX00 T0  CPX INX
        "000101000000100010000", --  12 B07  100XXX1X TX  STX TXA TXS
        "010101011010100010000", --  13 B08  1001101X T0  TXS
        "011001000000100010000", --  14 B09  101XXX1X T0  LDX TAX TSX
        "100110011001100010000", --  15 B10  1100101X T1X DEX
        "101010011001100100000", --  16 B11  11101000 T1X INX
        "011001011010100010000", --  17 B12  1011101X T0  TSX
        "100100011001100100000", --  18 B13  1X001000 T1X DEY INY
        "011001100000100100000", --  19 B14  101XX100 T0  LDY
        "011001000001100100000", --  20 B15  1010XX00 T0  LDY TAY
        "011001010101010100000", --  21 C01  00100000 T0  JSR
        "000101010101010100001", --  22 C02  00000000 T5  BRK
        "010100011001010100000", --  23 C03  0X001000 T0  Push
        "001010010101010100010", --  24 C04  01100000 T4  RTS
        "001000011001010100100", --  25 C05  0X101000 T3  Pull
        "000110010101010100001", --  26 C06  01000000 T5  RTI
        "001010000000010010000", --  27 C07  011XXX1X TX  ROR
        "000000000000000001000", --  28 C08  XXXXXXXX T2  T2 ANY
        "010110000000011000000", --  29 C09  010XXXX1 T0  EOR
        "000010101001010100000", --  30 C10  01X01100 TX  JMP (excluder for C11)
        "000000101001000001000", --  31 C11  XXX011XX T2  ALU absolute
        "010101000000011000000", --  32 C12  000XXXX1 T0  ORA
        "000000000100000001000", --  33 C13  XXXX0XXX T2  Left half (X0-X7)
        "010000000000000000000", --  34 C14  XXXXXXXX T0  T0 ANY
        "000000010001010101000", --  35 C15  0XX0X000 T2  BRK JSR RTI RTS Push/pull
        "000000000001010100100", --  36 C16  0XX0XX00 T3  BRK JSR RTI RTS Push/pull BIT JMP
        "000001010101010100010", --  37 D01  00X00000 T4  BRK JSR
        "000110010101010100010", --  38 D02  01000000 T4  RTI
        "000000010101001000100", --  39 D03  XXX000X1 T3  OP X, ind
        "000000010110001000010", --  40 D04  XXX100X1 T4  OP ind, Y
        "000000010110001001000", --  41 D05  XXX100X1 T2  OP ind, Y
        "000000001010000000100", --  42 D06  XXX11XXX T3  RIGHT ODD
        "001000011001010100000", --  43 D07  0X101000 TX  Pull
        "001010000000100010000", --  44 D08  111XXX1X TX  INC NOP
        "000000010101001000010", --  45 D09  XXX000X1 T4  OP X, ind
        "000000010110001000100", --  46 D10  XXX100X1 T3  OP ind, Y
        "000010010101010100000", --  47 D11  01X00000 TX  RTI RTS
        "001001010101010101000", --  48 D12  00100000 T2  JSR
        "010010000001100100000", --  49 D13  11X0XX00 T0  CPY CPX INY INX
        "010110000000101000000", --  50 D14  110XXXX1 T0  CMP
        "011010000000101000000", --  51 D15  111XXXX1 T0  SBC
        "011010000000001000000", --  52 D16  X11XXXX1 T0  ADC SBC
        "001001000000010010000", --  53 D17  001XXX1X TX  ROL
        "000010101001010100100", --  54 E01  01X01100 T3  JMP ind
        "000001000000010010000", --  55 E02  00XXXX1X TX  ASL ROL
        "001001010101010100001", --  56 E03  00100000 T5  JSR
        "000000010001010101000", --  57 E04  0XX0X000 T2  BRK JSR RTI RTS Push/pull
        "010101011010100100000", --  58 E05  10011000 T0  TYA
        "100000000000011000000", --  59 E06  0XXXXXX1 T1X UPPER ODD
        "101010000000001000000", --  60 E07  X11XXXX1 T1X ADC SBC
        "100000011001010010000", --  61 E08  0XX0101X T1X ASL ROL LSR ROR
        "010101011001100010000", --  62 E09  1000101X T0  TXA
        "011010011001010100000", --  63 E10  01101000 T0  PLA
        "011001000000101000000", --  64 E11  101XXXX1 T0  LDA
        "010000000000001000000", --  65 E12  XXXXXXX1 T0  ALL ODD
        "011001011001100100000", --  66 E13  10101000 T0  TAY
        "010000011001010010000", --  67 E14  0XX0101X T0  ASL ROL LSR ROR
        "011001011001100010000", --  68 E15  1010101X T0  TAX
        "011001100001010100000", --  69 E16  0010X100 T0  BIT0
        "011001000000011000000", --  70 E17  001XXXX1 T0  AND0
        "000000001010000000010", --  71 E18  XXX11XXX T4  OP abs,XY
        "000000010110001000001", --  72 E19  XXX100X1 T5  OP ind,Y
        "010000010110000100000", --  73 F01  XXX10000 T0  Branch T0
        "000110011001010101000", --  74 F02  01001000 T2  PHA
        "010010011001010010000", --  75 F03  01X0101X T0  LSR ROR
        "000010000000010010000", --  76 F04  01XXXX1X TX  LSR ROR
        "000101010101010101000", --  77 F05  00000000 T2  BRK
        "001001010101010100100", --  78 F06  00100000 T3  JSR
        "000101000000101000000", --  79 F07  100XXXX1 TX  STA
        "000000010110000101000", --  80 F08  XXX10000 T2  BR2 (Branch T2)
        "000000100100000001000", --  81 F09  XXXX01XX T2  zero page
        "000000010100001001000", --  82 F10  XXXX00X1 T2  ALU indirect
        "000000001000000001000", --  83 F11  XXXX1XXX T2  Right half (X8-XF)
        "001010010101010100001", --  84 F12  01100000 T5  RTS
        "000000000000000000010", --  85 F13  XXXXXXXX T4  T4 ANY
        "000000000000000000100", --  86 F14  XXXXXXXX T3  T3 ANY
        "010100010101010100000", --  87 F15  0X000000 T0  BRK RTI
        "010010101001010100000", --  88 F16  01X01100 T0  JMP
        "000000010101001000001", --  89 F17  XXX000X1 T5  OP X, ind
        "000000001000000000100", --  90 F18  XXXX1XXX T3  Right half (X8-XF)
        "000000010110001000010", --  91 G01  XXX100X1 T4  OP ind, Y
        "000000001010000000100", --  92 G02  XXX11XXX T3  RIGHT ODD
        "000000010110000100100", --  93 G03  XXX10000 T3  BR3 (Branch T3)
        "000100010101010100000", --  94 G04  0X000000 TX  BRK RTI
        "001001010101010100000", --  95 G05  00100000 TX  JSR
        "000010101001010100000", --  96 G06  01X01100 TX  JMP
        "000101000000100000000", --  97 G07  100XXXXX TX  STORE
        "000101010101010100010", --  98 G08  00000000 T4  BRK
        "000101011001010101000", --  99 G09  00001000 T2  PHP
        "000100011001010101000", -- 100 G10  0X001000 T2  Push
        "000010101001010100010", -- 101 G11  01X01100 T4  JMP ind
        "000010010101010100001", -- 102 G12  01X00000 T5  RTI RTS
        "001001010101010100001", -- 103 G13  00100000 T5  JSR
        "000110101001010101000", -- 104 H01  01001100 T2  JMP abs
        "001000011001010100100", -- 105 H02  0X101000 T3  Pull
        "000010000000000010000", -- 106 H03  X1XXXX1X TX  LSR ROR DEC INC DEX NOP
        "000001000000010010000", -- 107 H04  00XXXX1X TX  ASL ROL
        "010010011010010100000", -- 108 H05  01X11000 T0  CLI SEI
        "101001100001010100000", -- 109 H06  0010X100 T1X BIT
        "010001011010010100000", -- 110 H07  00X11000 T0  CLC SEC
        "000000100110000000100", -- 111 H08  XXX101XX T3  Memory zero page X/Y
        "101010000000001000000", -- 112 H09  X11XXXX1 T1X ADC SBC
        "011001100001010100000", -- 113 H10  0010X100 T0  BIT
        "011001011001010100000", -- 114 H11  00101000 T0  PLP
        "000110010101010100010", -- 115 H12  01000000 T4  RTI
        "100110000000101000000", -- 116 H13  110XXXX1 T1X CMP
        "100010101001100100000", -- 117 H14  11X01100 T1X CPY CPX abs
        "100001011001010010000", -- 118 H15  00X0101X T1X ASL ROL
        "100010000101100100000", -- 119 H16  11X00X00 T1X CPY CPX zpg/immed
        "010010011010100100000", -- 120 K01  11X11000 T0  CLD SED
        "000001000000000000000", -- 121 K02  X0XXXXXX TX  /IR6
        "000000101001000000100", -- 122 K03  XXX011XX T3  Memory absolute
        "000000100101000001000", -- 123 K04  XXX001XX T2  Memory zero page
        "000000010100001000001", -- 124 K05  XXXX00X1 T5  Memory indirect
        "000000001010000000010", -- 125 K06  XXX11XXX T4  Memory absolute X/Y
        "000000000000010000000", -- 126 K07  0XXXXXXX TX  /IR7
        "001001011010100100000", -- 127 K08  10111000 TX  CLV
        "000000011000000000000", -- 128 K09  XXXX10X0 TX  IMPL
        "000000011001010100000" -- 129 P/P  0XX01000 TX  Push/pull
    );

    alias IR: std_ulogic_vector(7 downto 0) is instruction_in;

    --! The 21 decoder input lines, in the order of the real chip's layout
    signal decoder_inputs: decoder_mask;
    --! Each line before the extra logic of lines 73, 83, 90 and 128
    signal lines: std_ulogic_vector(129 downto 0);
    --! Line 129: the stack push/pull instructions
    alias push_pull: std_ulogic is lines(129);
begin
    decoder_inputs <= (
        not cycle_T1X, not cycle_T0,
        not IR(5), IR(5), not IR(6), IR(6), not IR(2), IR(2),
        not IR(3), IR(3), not IR(4), IR(4), not IR(7), IR(7),
        not IR(0), IR(0) or IR(1), not IR(1),
        not cycle_T2, not cycle_T3, not cycle_T4, not cycle_T5
    );

    -- Each line is a NOR of the inputs it has a transistor on. This is a loop
    -- rather than a for-generate, since Copra can't stub generate scopes.
    process(decoder_inputs)
    begin
        for n in decoder_masks'range loop
            if (decoder_inputs and decoder_masks(n)) = (decoder_mask'range => '0') then
                lines(n) <= '1';
            else
                lines(n) <= '0';
            end if;
        end loop;
    end process;

    process(lines, previous_ready_PRDY, instruction_in)
    begin
        decoder_out <= lines;
        decoder_out(73) <= lines(73) and previous_ready_PRDY;
        decoder_out(83) <= lines(83) and not push_pull;
        decoder_out(90) <= lines(90) and not push_pull;
        decoder_out(128) <= lines(128) and not IR(0) and not push_pull;
    end process;
end architecture rtl;
