--! @file program_counter_high.vhdl
--! @brief Program Counter High register for the MOS 6502 CPU
--! @details Handles the high byte of the 16-bit program counter. Like
--! @ref program_counter_low, this is a select register (PCHS), increment
--! logic, and an output register (PCH). The select register loads either the
--! current PCH value (PCH/PCH) or the ADH bus (ADH/PCH), the increment logic
--! adds the carry out of PCL (PCLC), and PCH latches the result on phi2.
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
        --! @ref Ricoh_2A03_Phi2
        phi2            : in  std_ulogic;
        --! @ref Ricoh_2A03_Signal_PCH_DB
        signal_PCH_DB   : in  std_ulogic;
        --! @ref Ricoh_2A03_Signal_PCH_ADH
        signal_PCH_ADH  : in  std_ulogic;
        --! @ref Ricoh_2A03_PCLC, from @ref program_counter_low
        signal_PCLC     : in  std_ulogic;
        --! @ref Ricoh_2A03_Signal_PCH_PCH
        signal_PCH_PCH  : in  std_ulogic;
        --! @ref Ricoh_2A03_Signal_ADH_PCH
        signal_ADH_PCH  : in  std_ulogic;
        --! @ref Ricoh_2A03_ADH
        bus_ADH         : inout std_ulogic_vector(7 downto 0);
        --! @ref Ricoh_2A03_DB
        bus_DB          : inout std_ulogic_vector(7 downto 0);
        --! Clock to drive the select register's latch circuitry
        --! @ref metaclock
        metaclock       : in  std_ulogic
    );
end entity program_counter_high;

--! RTL architecture of the program counter high register
architecture rtl of program_counter_high is
    signal program_counter_register        : std_ulogic_vector(7 downto 0) := (others => '0');
    signal program_counter_select_register : std_ulogic_vector(7 downto 0) := (others => '0');
    --! Output of the increment logic, latched into PCH on phi2
    signal incremented_value               : std_ulogic_vector(7 downto 0);
    --! @ref Ricoh_2A03_PCHC Carry from the low nibble into the high nibble
    signal signal_PCHC                     : std_ulogic;
begin
    bus_DB  <= program_counter_register when signal_PCH_DB = '1' else (others => 'Z');
    bus_ADH <= program_counter_register when signal_PCH_ADH = '1' else (others => 'Z');

    -- The select register holds its value while neither PCH/PCH nor ADH/PCH
    -- is asserted, so it's sampled on the metaclock rather than inferring a
    -- latch.
    process(metaclock)
    begin
        if rising_edge(metaclock) then
            if signal_PCH_PCH = '1' then
                program_counter_select_register <= program_counter_register;
            elsif signal_ADH_PCH = '1' then
                program_counter_select_register <= bus_ADH;
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

    process(phi2)
    begin
        if rising_edge(phi2) then
            program_counter_register <= incremented_value;
        end if;
    end process;

end architecture rtl;
