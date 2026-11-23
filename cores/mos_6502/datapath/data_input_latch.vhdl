library ieee;
use ieee.std_logic_1164.all;

--! Data input latch for the MOS 6502, connected to the DB, ADL, and ADH buses
--! @details On the real chip, the data input latch is open during Phi2, and
--! keeps the value on the data pins when Phi2 falls, which is when external
--! memory has settled the bus. FPGA fabric can't synthesize a level-sensitive
--! latch cleanly, so `load` is sampled on the @ref metaclock instead, and the
--! latch follows the data pins one metaclock behind while it's high.
entity data_input_latch is
    port(
        --! Load signal for the register from the data input
        --! Should be wired to the clock generator Phi2 output
        load: in std_ulogic;
        --! The data to be loaded into the register, maps to D0-D7
        data_in: in std_ulogic_vector(7 downto 0);
        --! @ref MOS_6502_Signal_DL_DB
        db_bus_enable_DL_DB: in std_ulogic;
        --! @ref MOS_6502_DB
        db_bus_port: out std_ulogic_vector(7 downto 0);
        --! @ref MOS_6502_Signal_DL_ADH
        adh_bus_enable_DL_ADH: in std_ulogic;
        --! @ref MOS_6502_ADH
        adh_bus_port: out std_ulogic_vector(7 downto 0);
        --! @ref MOS_6502_Signal_DL_ADL
        adl_bus_enable_DL_ADL: in std_ulogic;
        --! @ref MOS_6502_ADL
        adl_bus_port: out std_ulogic_vector(7 downto 0);
        --! Clock to drive the latch circuitry
        --! @ref metaclock
        metaclock: in std_ulogic
    );
end entity;

architecture rtl of data_input_latch is
    signal register_data: std_ulogic_vector(7 downto 0) := (others => '0');
begin
    process(metaclock)
    begin
        if rising_edge(metaclock) then
            if load = '1' then
                register_data <= data_in;
            end if;
        end if;
    end process;

    db_bus_port <= register_data when db_bus_enable_DL_DB = '1' else (others => '1');
    adh_bus_port <= register_data when adh_bus_enable_DL_ADH = '1' else (others => '1');
    adl_bus_port <= register_data when adl_bus_enable_DL_ADL = '1' else (others => '1');
end architecture;
