library ieee;
use ieee.std_logic_1164.all;

--! @file
--! @brief Processor status register (P) for the 6502
--! @details Holds the C, Z, I, D, V and N flags (@ref MOS_6502_P_Register).
--! Each flag loads from whichever of its sources the random logic selects, and
--! holds its value otherwise.
--!
--! The flag load commands come from output latches in the
--! @ref random_logic_controller that are loaded during Phi2, so they stay high
--! through Phi2 as well as the Phi1 that follows. On the real chip, the flags
--! only take a new value during Phi1, while the buses hold valid data. During
--! Phi2 they just refresh. This register is sampled on the @ref metaclock
--! while `phi1` is high, so a flag can't pick up DB while it's precharging.
--!
--! If more than one source of a flag is selected at once, the flag holds its
--! value. The random logic never does that.
--!
--! The flags are also output to the random logic and the interrupt controller
--! (`*_OUT`), active-high, unlike the real chip.

--! Processor status register (P) for the 6502
--! @ref MOS_6502_P_Register
entity status_register is
    port(
        --! @ref Ricoh_2A03_Phi1. The flags only load while this is high.
        phi1: in std_ulogic;
        --! @ref Ricoh_2A03_DB, as resolved by @ref bus_multiplexer
        db_bus_in: in std_ulogic_vector(7 downto 0);
        --! Drives @ref Ricoh_2A03_DB, 'Z' when not enabled
        db_bus_out: out std_ulogic_vector(7 downto 0);
        --! @ref Ricoh_Signal_P_DB
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
        --! @ref Ricoh_Signal_0_V
        signal_0_V: in std_ulogic;
        --! @ref Ricoh_Signal_DB7_N
        signal_DB7_N: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_C_OUT
        carry_flag_C_OUT: out std_ulogic;
        --! @ref Ricoh_2A03_Signal_Z_OUT
        zero_flag_Z_OUT: out std_ulogic;
        --! @ref Ricoh_2A03_Signal_I_OUT
        interrupt_disable_I_OUT: out std_ulogic;
        --! @ref Ricoh_2A03_Signal_D_OUT
        decimal_flag_D_OUT: out std_ulogic;
        --! @ref Ricoh_2A03_Signal_V_OUT
        overflow_flag_V_OUT: out std_ulogic;
        --! @ref Ricoh_2A03_Signal_N_OUT
        negative_flag_N_OUT: out std_ulogic;
        --! Clock to drive the latch circuitry
        --! @ref metaclock
        metaclock: in std_ulogic
    );
end entity;

architecture rtl of status_register is
    signal DBZ: std_ulogic;
    signal register_data: std_ulogic_vector(7 downto 0) := (others => '0');
begin
    -- DBZ is high only when every bit of DB is low (a NOR of the whole bus)
    DBZ <= not (
        db_bus_in(0) or
        db_bus_in(1) or
        db_bus_in(2) or
        db_bus_in(3) or
        db_bus_in(4) or
        db_bus_in(5) or
        db_bus_in(6) or
        db_bus_in(7)
    );
    -- Bit 4 is straight up not wired to the DB bus at all, and 5 is hardwired as 1
    db_bus_out(7 downto 6) <= register_data(7 downto 6) when enable_P_DB = '1' else (others => 'Z');
    db_bus_out(5) <= '1' when enable_P_DB = '1' else 'Z';
    -- Bit 4 still needs an explicit 'Z' driver, or it defaults to 'U' and
    -- clobbers whatever else is driving DB(4)
    db_bus_out(4) <= 'Z';
    db_bus_out(3 downto 0) <= register_data(3 downto 0) when enable_P_DB = '1' else (others => 'Z');

    carry_flag_C_OUT <= register_data(0);
    zero_flag_Z_OUT <= register_data(1);
    interrupt_disable_I_OUT <= register_data(2);
    decimal_flag_D_OUT <= register_data(3);
    overflow_flag_V_OUT <= register_data(6);
    negative_flag_N_OUT <= register_data(7);

    process(metaclock)
        variable select_C: std_ulogic_vector(2 downto 0);
        variable select_Z: std_ulogic_vector(1 downto 0);
        variable select_I: std_ulogic_vector(1 downto 0);
        variable select_D: std_ulogic_vector(1 downto 0);
        variable select_V: std_ulogic_vector(3 downto 0);
    begin
        if rising_edge(metaclock) and phi1 = '1' then
            select_C := signal_DB0_C & signal_IR5_C & signal_ACR_C;
            case select_C is
                when "100" => register_data(0) <= db_bus_in(0);
                when "010" => register_data(0) <= signal_IR5;
                when "001" => register_data(0) <= signal_ACR;
                when others => null;
            end case;

            select_Z := signal_DB1_Z & signal_DBZ_Z;
            case select_Z is
                when "10" => register_data(1) <= db_bus_in(1);
                when "01" => register_data(1) <= DBZ;
                when others => null;
            end case;

            select_I := signal_DB2_I & signal_IR5_I;
            case select_I is
                when "10" => register_data(2) <= db_bus_in(2);
                when "01" => register_data(2) <= signal_IR5;
                when others => null;
            end case;

            select_D := signal_DB3_D & signal_IR5_D;
            case select_D is
                when "10" => register_data(3) <= db_bus_in(3);
                when "01" => register_data(3) <= signal_IR5;
                when others => null;
            end case;

            select_V := signal_DB6_V & signal_AVR_V & signal_1_V & signal_0_V;
            case select_V is
                when "1000" => register_data(6) <= db_bus_in(6);
                when "0100" => register_data(6) <= signal_AVR;
                when "0010" => register_data(6) <= '1';
                when "0001" => register_data(6) <= '0';
                when others => null;
            end case;

            if signal_DB7_N = '1' then
                register_data(7) <= db_bus_in(7);
            end if;
        end if;
    end process;
end architecture;
