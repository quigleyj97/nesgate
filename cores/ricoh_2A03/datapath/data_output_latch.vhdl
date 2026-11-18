library ieee;
use ieee.std_logic_1164.all;

--! Data output register (DOR) for the Ricoh 2A03, driving the data pins
--! @details The DOR is open during Phi1, and keeps the value DB settles to by
--! the end of it. During Phi2 of a write cycle (`R/W` low), the data bus
--! tristate buffers drive it onto the D0-D7 pins. Otherwise the real pins are
--! released, so memory can drive them. The FPGA fabric has no internal
--! tri-states, so here `data_out` reads all ones instead, and whatever reads
--! it uses `R/W` and Phi2 to tell a write from a released bus.
--!
--! FPGA fabric can't synthesize a level-sensitive latch cleanly, so Phi1 is
--! sampled on the @ref metaclock instead, and the register follows DB one
--! metaclock behind while it's high.
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
        --! Data output, connected to the D0-D7 pins. All ones (released)
        --! unless writing during Phi2.
        data_out: out std_ulogic_vector(7 downto 0);
        --! Clock to drive the latch circuitry
        --! @ref metaclock
        metaclock: in std_ulogic
    );
end entity;

architecture rtl of data_output_latch is
    signal register_data: std_ulogic_vector(7 downto 0) := (others => '0');
begin
    process(metaclock)
    begin
        if rising_edge(metaclock) then
            if phi1 = '1' then
                register_data <= data_in;
            end if;
        end if;
    end process;

    -- The data pins' tristate buffers are enabled by R/W and Phi2
    data_out <= register_data when signal_R_NOT_W = '0' and phi2 = '1'
        else (others => '1');
end architecture;
