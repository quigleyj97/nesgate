library ieee;
use ieee.std_logic_1164.all;

--! @file
--! @brief Predecode (PD) register for the MOS 6502
--! @details Holds the opcode read from the external data bus (D0-D7) so that
--! @ref predecode_logic can classify it before it reaches the instruction
--! register.
--!
--! On the real chip, the opcode passes through a transparent latch and then
--! the PD latch, which is open (transparent) for all of @ref MOS_6502_Phi2
--! and holds its value while Phi2 is low. The PD latch stores the opcode
--! inverted, but this core stores and outputs it in true form.
--!
--! FPGA fabric can't synthesize a level-sensitive latch cleanly, so Phi2 is
--! sampled on the @ref metaclock instead. While Phi2 is high the register
--! follows the data bus one metaclock behind, and keeps the last value it saw
--! before Phi2 fell, which is when external memory has settled the bus.

--! Predecode register, loaded from the external data bus during Phi2
entity predecode_register is
    port(
        --! @ref MOS_6502_Phi2. The register follows `data_in` while high
        --! and holds its value while low
        phi2: in std_ulogic;
        --! The external data bus, maps to D0-D7
        data_in: in std_ulogic_vector(7 downto 0);
        --! The latched opcode, fed to @ref predecode_logic
        predecode_out: out std_ulogic_vector(7 downto 0);
        --! Clock to drive the latch circuitry
        --! @ref metaclock
        metaclock: in std_ulogic
    );
end entity predecode_register;

architecture rtl of predecode_register is
    signal register_value: std_ulogic_vector(7 downto 0) := (others => '0');
begin
    process(metaclock)
    begin
        if rising_edge(metaclock) then
            if phi2 = '1' then
                register_value <= data_in;
            end if;
        end if;
    end process;

    predecode_out <= register_value;
end architecture rtl;
