--! @file program_counter_low.vhdl
--! @brief Program Counter Low register for the MOS 6502 CPU
--! @details Handles the low byte of the 16-bit program counter

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

--! Program Counter Low register entity
entity program_counter_low is
    port (
        --! @ref MOS_6502_Phi2
        phi2            : in  std_ulogic;
        --! @ref MOS_6502_Signal_PCL_DB
        signal_PCL_DB   : in  std_ulogic;
        --! @ref MOS_6502_Signal_PCL_ADL
        signal_PCL_ADL  : in  std_ulogic;
        --! @ref MOS_6502_Signal_I_PC
        signal_1_PC     : in  std_ulogic;
        --! @ref MOS_6502_Signal_PCL_PCL
        signal_PCL_PCL  : in  std_ulogic;
        --! @ref MOS_6502_Signal_ADL_PCL
        signal_ADL_PCL  : in  std_ulogic;
        --! @ref MOS_6502_PCLC, to @ref program_counter_high
        signal_PCLC     : out std_ulogic;
        --! @ref MOS_6502_ADL, as resolved by @ref bus_multiplexer
        bus_ADL_in      : in  std_ulogic_vector(7 downto 0);
        --! Drives @ref MOS_6502_ADL, all ones (released) when not enabled
        bus_ADL_out     : out std_ulogic_vector(7 downto 0);
        --! @ref MOS_6502_DB
        bus_DB          : out std_ulogic_vector(7 downto 0);
        --! Clock that samples the select register's and the program counter
        --! register's latch signals, @ref metaclock
        metaclock       : in  std_ulogic
    );
end entity program_counter_low;

--! RTL architecture of the program counter low register
architecture rtl of program_counter_low is
    -- Internal signals
    signal program_counter_register     : std_ulogic_vector(7 downto 0) := (others => '0');
    signal increment_register           : std_ulogic_vector(7 downto 0) := (others => '0');
    signal program_counter_select_register : std_ulogic_vector(7 downto 0) := (others => '0');
begin
    -- Output to DB bus when PCL_DB is asserted
    bus_DB <= program_counter_register when signal_PCL_DB = '1' else (others => '1');
    
    -- Output to ADL bus when PCL_ADL is asserted
    bus_ADL_out <= program_counter_register when signal_PCL_ADL = '1' else (others => '1');
    
    -- Process to handle program counter selection. The select register holds
    -- its value while neither PCL/PCL nor ADL/PCL is asserted, so it's sampled
    -- on the metaclock rather than inferring a latch.
    process(metaclock)
    begin
        if rising_edge(metaclock) then
            if signal_PCL_PCL = '1' then
                program_counter_select_register <= program_counter_register;
            elsif signal_ADL_PCL = '1' then
                program_counter_select_register <= bus_ADL_in;
            end if;
        end if;
    end process;
    
    -- Process to handle increment calculation
    process(program_counter_select_register, signal_1_PC)
        variable temp : unsigned(8 downto 0); -- 9 bits to capture carry
    begin
        if signal_1_PC = '1' then
            temp := resize(unsigned(program_counter_select_register), 9) + 1;
            increment_register <= std_ulogic_vector(temp(7 downto 0));
            signal_PCLC <= temp(8); -- Set carry out
        else
            increment_register <= program_counter_select_register;
            signal_PCLC <= '0';
        end if;
    end process;
    
    -- The program counter register is a latch that's open during Phi2, so
    -- it's sampled on the metaclock while Phi2 is high. The select register
    -- only loads while Phi2 is low, so the register can't count up more than
    -- once per Phi2.
    process(metaclock)
    begin
        if rising_edge(metaclock) then
            if phi2 = '1' then
                program_counter_register <= increment_register;
            end if;
        end if;
    end process;
    
end architecture rtl;