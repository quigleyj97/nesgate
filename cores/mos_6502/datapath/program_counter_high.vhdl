--! @file program_counter_high.vhdl
--! @brief Program Counter High register for the MOS 6502 CPU
--! @details Handles the high byte of the 16-bit program counter. Like
--! @ref program_counter_low, this is a select register (PCHS), increment
--! logic, and an output register (PCH). The select register loads either the
--! current PCH value (PCH/PCH) or the ADH bus (ADH/PCH), the increment logic
--! adds the carry out of PCL (PCLC), and PCH latches the result during phi2.
--!
--! The increment logic is split into two nibbles, as in Hanson's block
--! diagram: the low nibble increments on PCLC, and its carry out (PCHC)
--! increments the high nibble. There's no carry out of the high nibble, so
--! the program counter wraps from 0xFFFF to 0x0000.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

--! Program Counter High register entity
entity program_counter_high is
    port (
        --! @ref MOS_6502_Phi2
        phi2            : in  std_ulogic;
        --! @ref MOS_6502_Signal_PCH_DB
        signal_PCH_DB   : in  std_ulogic;
        --! @ref MOS_6502_Signal_PCH_ADH
        signal_PCH_ADH  : in  std_ulogic;
        --! @ref MOS_6502_PCLC, from @ref program_counter_low
        signal_PCLC     : in  std_ulogic;
        --! @ref MOS_6502_Signal_PCH_PCH
        signal_PCH_PCH  : in  std_ulogic;
        --! @ref MOS_6502_Signal_ADH_PCH
        signal_ADH_PCH  : in  std_ulogic;
        --! @ref MOS_6502_ADH, as resolved by @ref bus_multiplexer
        bus_ADH_in      : in  std_ulogic_vector(7 downto 0);
        --! Drives @ref MOS_6502_ADH, all ones (released) when not enabled
        bus_ADH_out     : out std_ulogic_vector(7 downto 0);
        --! @ref MOS_6502_DB
        bus_DB          : out std_ulogic_vector(7 downto 0);
        --! Clock that samples the select register's and the program counter
        --! register's latch signals, @ref metaclock
        metaclock       : in  std_ulogic
    );
end entity program_counter_high;

--! RTL architecture of the program counter high register
architecture rtl of program_counter_high is
    signal program_counter_register        : std_ulogic_vector(7 downto 0) := (others => '0');
    signal program_counter_select_register : std_ulogic_vector(7 downto 0) := (others => '0');
    --! Output of the increment logic, latched into PCH during phi2
    signal incremented_value               : std_ulogic_vector(7 downto 0);
    --! @ref MOS_6502_PCHC Carry from the low nibble into the high nibble
    signal signal_PCHC                     : std_ulogic;
begin
    bus_DB  <= program_counter_register when signal_PCH_DB = '1' else (others => '1');
    bus_ADH_out <= program_counter_register when signal_PCH_ADH = '1' else (others => '1');

    -- The select register holds its value while neither PCH/PCH nor ADH/PCH
    -- is asserted, so it's sampled on the metaclock rather than inferring a
    -- latch.
    process(metaclock)
    begin
        if rising_edge(metaclock) then
            if signal_PCH_PCH = '1' then
                program_counter_select_register <= program_counter_register;
            elsif signal_ADH_PCH = '1' then
                program_counter_select_register <= bus_ADH_in;
            end if;
        end if;
    end process;

    -- Increment logic (0-3): increments on the carry out of PCL
    signal_PCHC <= signal_PCLC when program_counter_select_register(3 downto 0) = "1111" else '0';
    incremented_value(3 downto 0) <= std_ulogic_vector(
        unsigned(program_counter_select_register(3 downto 0)) + unsigned'("" & signal_PCLC)
    );

    -- Increment logic (4-7): increments on the carry out of the low nibble
    incremented_value(7 downto 4) <= std_ulogic_vector(
        unsigned(program_counter_select_register(7 downto 4)) + unsigned'("" & signal_PCHC)
    );

    -- The program counter register is a latch that's open during Phi2, so
    -- it's sampled on the metaclock while Phi2 is high. The select register
    -- only loads while Phi2 is low, so the register can't count up more than
    -- once per Phi2.
    process(metaclock)
    begin
        if rising_edge(metaclock) then
            if phi2 = '1' then
                program_counter_register <= incremented_value;
            end if;
        end if;
    end process;

end architecture rtl;
