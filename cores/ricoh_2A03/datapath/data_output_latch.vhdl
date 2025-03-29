library ieee;
use ieee.std_logic_1164.all;

entity data_output_latch is
    port(
        --! @ref Ricoh_2A03_Phi1
        phi1: in std_ulogic;
        --! @ref Ricoh_2A03_Phi2
        phi2: in std_ulogic;
        --! @ref Ricoh_Signal_R_NOT_W
        signal_R_NOT_W: in std_ulogic;
        --! Data input, connected to the DB bus
        --! @ref Ricoh_2A03_DB
        data_in: in std_ulogic_vector(7 downto 0);
        --! Data output, connected to the D0-D7 pins
        data_out: out std_ulogic_vector(7 downto 0)
    );
end entity;

architecture rtl of data_output_latch is
    signal register_data: std_ulogic_vector(7 downto 0) := (others => '0');
begin
    process(phi1, data_in)
    begin
        if rising_edge(phi1) then
            register_data <= data_in;
        end if;
    end process;

    process(phi2)
    begin
        if rising_edge(phi2) then
            if signal_R_NOT_W = '0' then
                data_out <= register_data;
            else
                data_out <= (others => 'Z');
            end if;
        end if;
    end process;
end architecture;
