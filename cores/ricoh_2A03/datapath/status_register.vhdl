library ieee;
use ieee.std_logic_1164.all;

--! @file
--! @brief Processor status register (P) for the 6502
--! @details Holds the C, Z, I, D, V and N flags (@ref MOS_6502_P_Register).
--! Each flag loads from whichever of its sources the random logic selects, and
--! holds its value while none is selected.
--!
--! The flag load commands come from output latches in the
--! @ref random_logic_controller that are loaded during Phi2, so they stay high
--! through Phi2 as well as the Phi1 that follows. On the real chip, the flags
--! only take a new value during Phi1, while the buses hold valid data. During
--! Phi2 they just refresh. This register is sampled on the @ref metaclock
--! while `phi1` is high, so a flag can't pick up DB while it's precharging.
--!
--! On the real chip, each source's select signal opens a pass MOSFET onto the
--! flag latch's input node, so if more than one is selected at once, a 0 from
--! any of them pulls the node low: the flag loads the AND of every selected
--! source. This register does the same, like the wired-AND buses. The
--! random logic never selects two sources at once, but unofficial opcodes
--! might.
--!
--! The flags are also output to the random logic and the interrupt controller
--! (`*_OUT`), active-high, unlike the real chip.
--!
--! There's no B flag in the register. When P is pushed (`P/DB`), bit 4 comes
--! from @ref Ricoh_2A03_Signal_B_OUT instead, so BRK and PHP push it set, and
--! a hardware interrupt pushes it clear. Bit 5 is always pushed set.
--!
--! @ref Ricoh_2A03_Signal_BRK6E, at the end of the BRK sequence, sets I. On the
--! real chip it forces `I_OUT` high, and the I latch is refreshed from
--! `I_OUT`, so I reads as set right away, and stays set once BRK6E ends. Here,
--! I reads as set during BRK6E, and loads a 1 during the Phi1 it covers, unless
--! `DB2/I` or `IR5/I` loads it instead.

--! Processor status register (P) for the 6502
--! @ref MOS_6502_P_Register
entity status_register is
    port(
        --! @ref Ricoh_2A03_Phi1. The flags only load while this is high.
        phi1: in std_ulogic;
        --! @ref Ricoh_2A03_DB, as resolved by @ref bus_multiplexer
        db_bus_in: in std_ulogic_vector(7 downto 0);
        --! Drives @ref Ricoh_2A03_DB, all ones (released) when not enabled
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
        --! @ref Ricoh_2A03_Signal_BRK6E, which sets I
        brk_cycle_6_end_BRK6E: in std_ulogic;
        --! @ref Ricoh_2A03_Signal_B_OUT, pushed as bit 4
        break_flag_B_OUT: in std_ulogic;
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
    -- Bit 4 is the B flag from the interrupt logic, and bit 5 is hardwired as
    -- 1. While P/DB is low, every bit reads 1, releasing DB.
    db_bus_out <= register_data(7 downto 6) & '1' & break_flag_B_OUT & register_data(3 downto 0)
        when enable_P_DB = '1' else (others => '1');

    carry_flag_C_OUT <= register_data(0);
    zero_flag_Z_OUT <= register_data(1);
    interrupt_disable_I_OUT <= register_data(2) or brk_cycle_6_end_BRK6E;
    decimal_flag_D_OUT <= register_data(3);
    overflow_flag_V_OUT <= register_data(6);
    negative_flag_N_OUT <= register_data(7);

    process(metaclock)
        -- What a source puts on a flag's input node: its value while
        -- selected, or 1 (released) while not, so the node reads the AND of
        -- every selected source
        function source(selected: std_ulogic; value: std_ulogic) return std_ulogic is
        begin
            return value or not selected;
        end function;
    begin
        if rising_edge(metaclock) and phi1 = '1' then
            if (signal_DB0_C or signal_IR5_C or signal_ACR_C) = '1' then
                register_data(0) <= source(signal_DB0_C, db_bus_in(0))
                    and source(signal_IR5_C, signal_IR5)
                    and source(signal_ACR_C, signal_ACR);
            end if;

            if (signal_DB1_Z or signal_DBZ_Z) = '1' then
                register_data(1) <= source(signal_DB1_Z, db_bus_in(1))
                    and source(signal_DBZ_Z, DBZ);
            end if;

            if (signal_DB2_I or signal_IR5_I) = '1' then
                register_data(2) <= source(signal_DB2_I, db_bus_in(2))
                    and source(signal_IR5_I, signal_IR5);
            elsif brk_cycle_6_end_BRK6E = '1' then
                register_data(2) <= '1';
            end if;

            if (signal_DB3_D or signal_IR5_D) = '1' then
                register_data(3) <= source(signal_DB3_D, db_bus_in(3))
                    and source(signal_IR5_D, signal_IR5);
            end if;

            -- 1/V selects a source that's always 1, and 0/V one that's
            -- always 0
            if (signal_DB6_V or signal_AVR_V or signal_1_V or signal_0_V) = '1' then
                register_data(6) <= source(signal_DB6_V, db_bus_in(6))
                    and source(signal_AVR_V, signal_AVR)
                    and not signal_0_V;
            end if;

            if signal_DB7_N = '1' then
                register_data(7) <= db_bus_in(7);
            end if;
        end if;
    end process;
end architecture;
