library ieee;
use ieee.std_logic_1164.all;

--! Processor status register (P) for the 6502
--! @ref MOS_6502_P_Register
entity status_register is
    port(
        --! @ref Ricoh_2A03_DB
        db_bus: inout std_ulogic_vector(7 downto 0);
        --! @ref Ricoh_2A03_Signal_P_DB
        enable_P_DB: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_IR5
        signal_IR5: in std_ulogic;
        --! @ref Ricoh2A03_ALU_ACR
        signal_ACR: in std_ulogic;
        --! @ref Ricoh2A03_ALU_AVR
        signal_AVR: in std_ulogic;
        --! @ref Ricoh_Signal_DB0_C
        signal_DB0_C: in std_ulogic;
        --! @ref Ricoh_Signal_IR5_C
        signal_IR5_C: in std_ulogic;
        --! @ref Ricoh_Signal_ACR_C
        signal_ACR_C: in std_ulogic;
        --! @ref Ricoh_Signal_DB1_Z
        signal_DB1_Z: in std_ulogic;
        --! @ref Ricoh_Signal_DBZ_Z
        signal_DBZ_Z: in std_ulogic;
        --! @ref Ricoh_Signal_DB2_I
        signal_DB2_I: in std_ulogic;
        --! @ref Ricoh_Signal_IR5_I
        signal_IR5_I: in std_ulogic;
        --! @ref Ricoh_Signal_DB3_D
        signal_DB3_D: in std_ulogic;
        --! @ref Ricoh_Signal_IR5_D
        signal_IR5_D: in std_ulogic;
        --! @ref Ricoh_Signal_DB6_V
        signal_DB6_V: in std_ulogic;
        --! @ref Ricoh_Signal_AVR_V
        signal_AVR_V: in std_ulogic;
        --! @ref Ricoh_Signal_1_V
        signal_1_V: in std_ulogic;
        --! @ref Ricoh_Signal_DB7_N
        signal_DB7_N: in std_ulogic
    );
end entity;

architecture rtl of status_register is
    signal DBZ: std_ulogic;
    signal register_data: std_ulogic_vector(7 downto 0);
begin
    DBZ <= not (
        db_bus(1) and
        db_bus(2) and
        db_bus(3) and
        db_bus(4) and
        db_bus(5) and
        db_bus(6) and
        db_bus(7)
    );
    -- Bit 4 is straight up not wired to the DB bus at all, and 5 is hardwired as 1
    db_bus(7 downto 6) <= register_data(7 downto 6) when enable_P_DB = '1' else (others => 'Z');
    db_bus(5) <= '1' when enable_P_DB = '1' else 'Z';
    db_bus(3 downto 0) <= register_data(3 downto 0) when enable_P_DB = '1' else (others => 'Z');

    process(signal_DB0_C, signal_IR5_C, signal_ACR_C)
        variable sensitivity: std_ulogic_vector(2 downto 0);
    begin
        sensitivity := signal_DB0_C & signal_IR5_C & signal_ACR_C;
        case sensitivity is
            when "100" =>
                register_data(0) <= db_bus(0);
            when "010" =>
                register_data(0) <= signal_IR5;
            when "001" =>
                register_data(0) <= signal_ACR;
            when others =>
                register_data(0) <= register_data(0);
        end case;
    end process;

    process(signal_DB1_Z, signal_DBZ_Z)
        variable sensitivity: std_ulogic_vector(1 downto 0);
    begin
        sensitivity := signal_DB1_Z & signal_DBZ_Z;
        case sensitivity is
            when "10" =>
                register_data(1) <= db_bus(1);
            when "01" =>
                register_data(1) <= DBZ;
            when others =>
                register_data(1) <= register_data(1);
        end case;
    end process;

    process(signal_DB2_I, signal_IR5_I)
        variable sensitivity: std_ulogic_vector(1 downto 0);
    begin
        sensitivity := signal_DB2_I & signal_IR5_I;
        case sensitivity is
            when "10" =>
                register_data(2) <= db_bus(2);
            when "01" =>
                register_data(2) <= signal_IR5;
            when others =>
                register_data(2) <= register_data(2);
        end case;
    end process;

    process(signal_DB3_D, signal_IR5_D)
        variable sensitivity: std_ulogic_vector(1 downto 0);
    begin
        sensitivity := signal_DB3_D & signal_IR5_D;
        case sensitivity is
            when "10" =>
                register_data(3) <= db_bus(3);
            when "01" =>
                register_data(3) <= signal_IR5;
            when others =>
                register_data(3) <= register_data(3);
        end case;
    end process;

    process(signal_DB6_V, signal_AVR_V, signal_1_V)
        variable sensitivity: std_ulogic_vector(2 downto 0);
    begin
        sensitivity := signal_DB6_V & signal_AVR_V & signal_1_V;
        case sensitivity is
            when "100" =>
                register_data(6) <= db_bus(6);
            when "010" =>
                register_data(6) <= signal_AVR;
            when "001" =>
                register_data(6) <= signal_1_V;
            when others =>
                register_data(6) <= register_data(6);
        end case;
    end process;

    process(signal_DB7_N)
    begin
        case (signal_DB7_N) is
            when '1' =>
                register_data(7) <= db_bus(7);
            when others =>
                register_data(7) <= signal_DB7_N;
        end case;
    end process;
end architecture;
