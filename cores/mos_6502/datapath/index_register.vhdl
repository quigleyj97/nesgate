library ieee;
use ieee.std_logic_1164.all;

--! @brief Index register for the MOS 6502
--! Can model any one-output, one-input CPU register
--! @details On the real chip, these registers are latches that are open while
--! their load signal is asserted, and keep the last value they saw. FPGA
--! fabric can't synthesize a level-sensitive latch cleanly, so `load` is
--! sampled on the @ref metaclock instead, and the register follows `data_in`
--! one metaclock behind while it's asserted. Sampling a level, rather than
--! loading on the edge of `load`, also means the register doesn't race the
--! bus it loads from, which often starts being driven at the same moment.
entity index_register is
    port(
        data_in: in std_ulogic_vector(7 downto 0);
        load: in std_ulogic;
        data_out: out std_ulogic_vector(7 downto 0);
        output_enable: in std_ulogic;
        --! Clock to drive the latch circuitry
        --! @ref metaclock
        metaclock: in std_ulogic
    );
end entity;

architecture rtl of index_register is
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

    data_out <= register_data when output_enable = '1' else (others => '1');
end architecture;
