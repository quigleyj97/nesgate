--! @file ulx3s_85k.vhdl
--! @brief Synthesis top level for the ULX3S (ECP5-85k)
--! @details Runs the @ref mos_6502 CPU from a small ROM, with a memory map
--! loosely following the NES:
--!
--! | Address         | Contents                                      |
--! |-----------------|-----------------------------------------------|
--! | `$0000`-`$1FFF` | 2 KiB of RAM, mirrored four times             |
--! | `$6000`         | The LEDs (write, and read back)               |
--! | `$8000`-`$FFFF` | 256 bytes of ROM, mirrored                    |
--!
--! The ROM counts up on the LEDs, a few times a second. Everything is clocked
--! from the 25 MHz oscillator, which is the CPU's @ref metaclock. Each of Phi1
--! and Phi2 lasts 7 metaclock cycles, so the CPU runs at 25 MHz / 14, about
--! 1.786 MHz, close to the NTSC NES's 1.79 MHz.
--!
--! FIRE1 resets the CPU. It's also held in reset for a while after the FPGA
--! is configured.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity toplevel is
    port (
        clk_25mhz: in std_ulogic;
        led: out std_ulogic_vector(7 downto 0);
        btn: in std_ulogic_vector(6 downto 0)
    );
end entity;

architecture rtl of toplevel is
    component mos_6502 is
        port (
            metaclock: in std_ulogic;
            phi1: in std_ulogic;
            phi2: in std_ulogic;
            reset_pin_n_RES: in std_ulogic;
            irq_pin_n_IRQ: in std_ulogic;
            nmi_pin_n_NMI: in std_ulogic;
            ready_pin_RDY: in std_ulogic;
            address: out std_ulogic_vector(15 downto 0);
            data_in: in std_ulogic_vector(7 downto 0);
            data_out: out std_ulogic_vector(7 downto 0);
            read_not_write_R_NOT_W: out std_ulogic;
            sync_SYNC: out std_ulogic
        );
    end component;
    component clock_divider is
        generic(
            divide_by: natural := 2
        );
        port(
            clk: in std_ulogic;
            clk_out: out std_ulogic
        );
    end component;
    for cpu: mos_6502 use entity work.mos_6502;
    for phase_clock: clock_divider use entity work.clock_divider;

    --! Metaclock cycles per phase. Must be at least 3.
    constant METACLOCKS_PER_PHASE: natural := 7;

    type rom_type is array(0 to 255) of std_ulogic_vector(7 downto 0);
    --! The program, at `$FF00`. The delay loop runs 256 x 256 times, about
    --! 330,000 cycles.
    constant ROM: rom_type := (
        -- reset:
        16#00# => x"A2", 16#01# => x"FF",                   -- LDX #$FF
        16#02# => x"9A",                                    -- TXS
        16#03# => x"A9", 16#04# => x"00",                   -- LDA #$00
        16#05# => x"85", 16#06# => x"00",                   -- STA $00
        -- loop:
        16#07# => x"A5", 16#08# => x"00",                   -- LDA $00
        16#09# => x"8D", 16#0A# => x"00", 16#0B# => x"60",  -- STA $6000
        16#0C# => x"E6", 16#0D# => x"00",                   -- INC $00
        16#0E# => x"A2", 16#0F# => x"00",                   -- LDX #$00
        -- outer:
        16#10# => x"A0", 16#11# => x"00",                   -- LDY #$00
        -- inner:
        16#12# => x"88",                                    -- DEY
        16#13# => x"D0", 16#14# => x"FD",                   -- BNE inner
        16#15# => x"CA",                                    -- DEX
        16#16# => x"D0", 16#17# => x"F8",                   -- BNE outer
        16#18# => x"4C", 16#19# => x"07", 16#1A# => x"FF",  -- JMP loop
        -- Every vector points at reset
        16#FA# => x"00", 16#FB# => x"FF",
        16#FC# => x"00", 16#FD# => x"FF",
        16#FE# => x"00", 16#FF# => x"FF",
        others => x"EA"                                     -- NOP
    );

    type ram_type is array(0 to 2047) of std_ulogic_vector(7 downto 0);
    signal ram: ram_type := (others => (others => '0'));

    signal phase: std_ulogic;
    signal phi1: std_ulogic;
    signal phi2: std_ulogic;

    --! Counts metaclock cycles after configuration, holding the CPU in reset
    --! until it's done
    signal power_on_count: unsigned(9 downto 0) := (others => '0');
    signal power_on_done: std_ulogic := '0';
    signal n_reset: std_ulogic;

    signal address: std_ulogic_vector(15 downto 0);
    signal data_in: std_ulogic_vector(7 downto 0) := (others => '0');
    signal data_out: std_ulogic_vector(7 downto 0);
    signal read_not_write: std_ulogic;

    signal ram_data: std_ulogic_vector(7 downto 0) := (others => '0');
    signal rom_data: std_ulogic_vector(7 downto 0) := (others => '0');
    signal led_register: std_ulogic_vector(7 downto 0) := (others => '0');

    signal ram_selected: boolean;
    signal led_selected: boolean;
    signal rom_selected: boolean;
    --! Memory stores the CPU's data during Phi2 of a write cycle
    signal writing: boolean;
begin
    phase_clock: clock_divider
        generic map(divide_by => METACLOCKS_PER_PHASE)
        port map(clk => clk_25mhz, clk_out => phase);
    phi1 <= not phase;
    phi2 <= phase;

    process(clk_25mhz)
    begin
        if rising_edge(clk_25mhz) then
            if power_on_done = '0' then
                power_on_count <= power_on_count + 1;
                if power_on_count = (power_on_count'range => '1') then
                    power_on_done <= '1';
                end if;
            end if;
        end if;
    end process;
    -- FIRE1 is active-high
    n_reset <= power_on_done and not btn(1);

    cpu: mos_6502
        port map(
            metaclock => clk_25mhz,
            phi1 => phi1,
            phi2 => phi2,
            reset_pin_n_RES => n_reset,
            irq_pin_n_IRQ => '1',
            nmi_pin_n_NMI => '1',
            ready_pin_RDY => '1',
            address => address,
            data_in => data_in,
            data_out => data_out,
            read_not_write_R_NOT_W => read_not_write,
            sync_SYNC => open
        );

    ram_selected <= address(15 downto 13) = "000";
    led_selected <= address = x"6000";
    rom_selected <= address(15) = '1';
    writing <= phi2 = '1' and read_not_write = '0';

    -- The address is stable from the end of Phi1, so memory has all of Phi2
    -- to answer. Reads take a metaclock cycle, so the RAM can be block RAM.
    process(clk_25mhz)
    begin
        if rising_edge(clk_25mhz) then
            if writing and ram_selected then
                ram(to_integer(unsigned(address(10 downto 0)))) <= data_out;
            end if;
            ram_data <= ram(to_integer(unsigned(address(10 downto 0))));
            rom_data <= ROM(to_integer(unsigned(address(7 downto 0))));
            if writing and led_selected then
                led_register <= data_out;
            end if;
        end if;
    end process;

    data_in <= ram_data when ram_selected
        else led_register when led_selected
        else rom_data when rom_selected
        else (others => '0');

    led <= led_register;
end architecture;
