--! @file program_counter_low.vhdl
--! @brief Program Counter Low register for the MOS 6502 CPU
--! @details Handles the low byte of the 16-bit program counter

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

--! Program Counter Low register entity
entity program_counter_low is
    port (
        --! @ref Clock_PHI2 System clock signal
        phi2            : in  std_ulogic;
        --! @ref Signal_PCL_DB Program counter low value to data bus
        signal_PCL_DB   : in  std_ulogic;
        --! @ref Signal_PCL_ADL Program counter low value to address low bus
        signal_PCL_ADL  : in  std_ulogic;
        --! @ref Signal_1_PC Increment program counter
        signal_1_PC     : in  std_ulogic;
        --! @ref Signal_PCL_PCL Store program counter low value
        signal_PCL_PCL  : in  std_ulogic;
        --! @ref Signal_ADL_PCL Load PCL from address low bus
        signal_ADL_PCL  : in  std_ulogic;
        --! @ref Signal_PCLC Program counter low carry output
        signal_PCLC     : out std_ulogic;
        --! @ref Bus_ADL Address low bus
        bus_ADL         : inout std_ulogic_vector(7 downto 0);
        --! @ref Bus_DB Data bus
        bus_DB          : inout std_ulogic_vector(7 downto 0)
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
    bus_DB <= program_counter_register when signal_PCL_DB = '1' else (others => 'Z');
    
    -- Output to ADL bus when PCL_ADL is asserted
    bus_ADL <= program_counter_register when signal_PCL_ADL = '1' else (others => 'Z');
    
    -- Process to handle program counter selection
    process(signal_PCL_PCL, signal_ADL_PCL, program_counter_register, bus_ADL)
    begin
        if signal_PCL_PCL = '1' then
            program_counter_select_register <= program_counter_register;
        elsif signal_ADL_PCL = '1' then
            program_counter_select_register <= bus_ADL;
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
    
    -- Process to update program counter register on clock edge
    process(phi2)
    begin
        if rising_edge(phi2) then
            program_counter_register <= increment_register;
        end if;
    end process;
    
end architecture rtl;