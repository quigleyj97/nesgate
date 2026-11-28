library ieee;
use ieee.std_logic_1164.all;

--! @file
--! @brief The I/O ports: the `OUT0`-`OUT2` pins, written through `$4016`, and
--! the `/IN0` and `/IN1` strobes for reading `$4016` and `$4017`
--! @details Writing `$4016` stores bits 2-0 in a register. Each pin's output
--! latch copies its bit during ACLK2, so the pins change at the next APU cycle
--! boundary, up to two CPU cycles after the write. On the NES `OUT0` is the
--! controllers' strobe.
--!
--! The `/IN0` and `/IN1` pins are the register decoder's `R4016` and `R4017`,
--! inverted, for the whole of a read of `$4016` or `$4017`. The data comes in
--! through the data pins, like any other read.
--!
--! During reset the real chip floats all five pins. This entity keeps driving
--! them. Every latch is sampled on the @ref metaclock while its enable is
--! high.
entity io_ports is
    port(
        --! @ref Ricoh_2A03_Signal_ACLK2
        aclk2: in std_ulogic;
        --! The internal data bus (@ref Ricoh_2A03_DB)
        bus_DB_in: in std_ulogic_vector(7 downto 0);
        --! `W4016`, from the @ref register_decoder
        write_W4016: in std_ulogic;
        --! `R4016`, from the @ref register_decoder
        read_R4016: in std_ulogic;
        --! `R4017`, from the @ref register_decoder
        read_R4017: in std_ulogic;
        --! The `OUT0`-`OUT2` pins
        out_pins_OUT: out std_ulogic_vector(2 downto 0);
        --! The `/IN0` pin (active-low)
        in0_pin_n_IN0: out std_ulogic;
        --! The `/IN1` pin (active-low)
        in1_pin_n_IN1: out std_ulogic;
        --! @ref metaclock
        metaclock: in std_ulogic
    );
end entity io_ports;

architecture rtl of io_ports is
    --! The `$4016` register
    signal out_register: std_ulogic_vector(2 downto 0) := (others => '0');
    --! The pins' output latches, loaded during ACLK2
    signal out_latches: std_ulogic_vector(2 downto 0) := (others => '0');
begin
    process(metaclock)
    begin
        if rising_edge(metaclock) then
            if write_W4016 = '1' then
                out_register <= bus_DB_in(2 downto 0);
            end if;
            if aclk2 = '1' then
                out_latches <= out_register;
            end if;
        end if;
    end process;

    out_pins_OUT <= out_latches;
    in0_pin_n_IN0 <= not read_R4016;
    in1_pin_n_IN1 <= not read_R4017;
end architecture rtl;
