library ieee;
use ieee.std_logic_1164.all;

--! @tparam divide_by The number of times to divide the input clock by
--! @param[in] clk The input clock to divide by
--! @param[out] clk_out The divided clock signal
--!
--! @brief
--! A simple clock divider that takes an input clock and outputs a slower clock signal
--! where each rising edge of the output clock happens after `divide_by` rising edges
--! from the input clock, and the output is held high for another `divide_by` rising
--! edges of the input clock.
--!
entity clock_divider is
    generic(
        --! How many times to divid
        divide_by: natural := 2
    );
    port(
        clk: in std_ulogic;
        clk_out: out std_ulogic := '0'
    );
end entity clock_divider;

architecture rtl of clock_divider is
    signal counter: natural range 0 to divide_by - 1 := 0;
    signal output_value: std_ulogic := '0';
begin

    clk_out <= output_value;
    process(clk)
    begin
        if rising_edge(clk) then
            if counter = divide_by - 1 then
                output_value <= not output_value;
                counter <= 0;
            else
                counter <= counter + 1;
            end if;
        end if;
    end process;
end rtl;