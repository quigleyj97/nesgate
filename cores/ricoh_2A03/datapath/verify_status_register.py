from typing import TYPE_CHECKING

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer

if TYPE_CHECKING:
    from status_register import StatusRegister as DUT

LOAD_SIGNALS = [
    "signal_DB0_C",
    "signal_IR5_C",
    "signal_ACR_C",
    "signal_DB1_Z",
    "signal_DBZ_Z",
    "signal_DB2_I",
    "signal_IR5_I",
    "signal_DB3_D",
    "signal_IR5_D",
    "signal_DB6_V",
    "signal_AVR_V",
    "signal_1_V",
    "signal_0_V",
    "signal_DB7_N",
]
DB_LOADS = ["signal_DB0_C", "signal_DB1_Z", "signal_DB2_I", "signal_DB3_D", "signal_DB6_V", "signal_DB7_N"]


async def reset(dut: "DUT"):
    """Start the metaclock, deassert every input, and clear the flags."""
    cocotb.start_soon(Clock(dut.metaclock, 1, unit="ns").start())
    dut.phi1.value = 0
    for name in LOAD_SIGNALS:
        getattr(dut, name).value = 0
    dut.signal_IR5.value = 0
    dut.brk_cycle_6_end_BRK6E.value = 0
    dut.break_flag_B_OUT.value = 1
    dut.signal_ACR.value = 0
    dut.signal_AVR.value = 0
    dut.enable_P_DB.value = 0
    dut.db_bus_in.value = 0
    await Timer(1, unit="ns")
    await load(dut, *DB_LOADS)
    assert dut.register_data.value == 0


async def phi1_phase(dut: "DUT"):
    """Run one Phi1 phase, long enough for several metaclock edges."""
    dut.phi1.value = 1
    await Timer(4, unit="ns")
    dut.phi1.value = 0
    await Timer(1, unit="ns")


async def load(dut: "DUT", *names: str):
    """Assert the given load commands through a Phi1 phase, then release them."""
    for name in names:
        getattr(dut, name).value = 1
    await phi1_phase(dut)
    for name in names:
        getattr(dut, name).value = 0
    await Timer(1, unit="ns")


@cocotb.test()
async def test_status_register_data_bus(dut: "DUT"):
    await reset(dut)
    assert dut.DBZ.value == 1

    # Loading every flag from DB = 0xFF doesn't touch bits 4 and 5
    dut.db_bus_in.value = 0b11111111
    await Timer(1, unit="ns")
    assert dut.DBZ.value == 0
    await load(dut, *DB_LOADS)
    assert dut.register_data.value == 0b11001111

    # Bit 5 reads 1 on DB, and bit 4 is B_OUT
    dut.db_bus_in.value = 0
    dut.enable_P_DB.value = 1
    await Timer(1, unit="ns")
    assert dut.db_bus_out.value == 0b11111111
    dut.break_flag_B_OUT.value = 0
    await Timer(1, unit="ns")
    assert dut.db_bus_out.value == 0b11101111, "Bit 4 should follow B_OUT"
    dut.break_flag_B_OUT.value = 1
    dut.enable_P_DB.value = 0
    await Timer(1, unit="ns")
    assert not dut.db_bus_out.value.is_resolvable


@cocotb.test()
async def test_flag_outputs(dut: "DUT"):
    """Each flag is output on its own port."""
    await reset(dut)
    outputs = {
        0: dut.carry_flag_C_OUT,
        1: dut.zero_flag_Z_OUT,
        2: dut.interrupt_disable_I_OUT,
        3: dut.decimal_flag_D_OUT,
        6: dut.overflow_flag_V_OUT,
        7: dut.negative_flag_N_OUT,
    }
    for bit in outputs:
        dut.db_bus_in.value = 1 << bit
        await load(dut, *DB_LOADS)
        for other_bit, other_port in outputs.items():
            assert other_port.value == (1 if other_bit == bit else 0), (
                f"DB = {1 << bit:#04x}: flag {other_bit} should be {int(other_bit == bit)}"
            )


@cocotb.test()
async def test_loads_only_during_phi1(dut: "DUT"):
    """A load command outside Phi1 (e.g. while DB precharges in Phi2) doesn't change the flags."""
    await reset(dut)
    dut.db_bus_in.value = 0xFF
    for name in DB_LOADS:
        getattr(dut, name).value = 1
    await Timer(5, unit="ns")
    assert dut.register_data.value == 0, "Flags loaded outside Phi1"

    # The flags take the DB value of Phi1, even if the commands stay high after it
    dut.db_bus_in.value = 0b1000_0001
    await phi1_phase(dut)
    dut.db_bus_in.value = 0xFF
    await Timer(5, unit="ns")
    assert dut.register_data.value == 0b1000_0001


@cocotb.test()
async def test_status_register_alu_flags(dut: "DUT"):
    await reset(dut)
    dut.signal_ACR.value = 1
    dut.signal_AVR.value = 1
    await load(dut, "signal_ACR_C", "signal_AVR_V")
    assert dut.register_data.value == 0b0100_0001
    dut.signal_ACR.value = 0
    dut.signal_AVR.value = 0
    await load(dut, "signal_ACR_C", "signal_AVR_V")
    assert dut.register_data.value == 0b0000_0000


@cocotb.test()
async def test_status_register_ir5(dut: "DUT"):
    await reset(dut)
    dut.signal_IR5.value = 1
    await load(dut, "signal_IR5_C", "signal_IR5_I", "signal_IR5_D")
    assert dut.register_data.value == 0b0000_1101
    dut.signal_IR5.value = 0
    await load(dut, "signal_IR5_C", "signal_IR5_I", "signal_IR5_D")
    assert dut.register_data.value == 0b0000_0000


@cocotb.test()
async def test_set_and_clear_v(dut: "DUT"):
    """1/V sets V (the SO pin), and 0/V clears it (CLV)."""
    await reset(dut)
    await load(dut, "signal_1_V")
    assert dut.overflow_flag_V_OUT.value == 1
    assert dut.register_data.value == 0b0100_0000
    await load(dut, "signal_0_V")
    assert dut.overflow_flag_V_OUT.value == 0
    assert dut.register_data.value == 0


@cocotb.test()
async def test_status_register_dbz(dut: "DUT"):
    """DBZ/Z sets Z only when every bit of DB is zero."""
    await reset(dut)
    await load(dut, "signal_DBZ_Z")
    assert dut.register_data.value == 0b0000_0010
    # Any single set bit, including bit 0, means DB isn't zero
    for bit in range(8):
        dut.db_bus_in.value = 1 << bit
        await Timer(1, unit="ns")
        assert dut.DBZ.value == 0, f"DBZ high with DB = {1 << bit:#04x}"
    for value in [0x7F, 0xFE, 0xFF]:
        dut.db_bus_in.value = value
        await Timer(1, unit="ns")
        assert dut.DBZ.value == 0, f"DBZ high with DB = {value:#04x}"
    await load(dut, "signal_DBZ_Z")
    assert dut.register_data.value == 0


@cocotb.test()
async def test_brk6e_sets_i(dut: "DUT"):
    """BRK6E sets I: it reads as set right away, and stays set afterwards."""
    await reset(dut)
    assert dut.interrupt_disable_I_OUT.value == 0
    dut.brk_cycle_6_end_BRK6E.value = 1
    await Timer(1, unit="ns")
    assert dut.interrupt_disable_I_OUT.value == 1, "I didn't read as set during BRK6E"
    await phi1_phase(dut)
    dut.brk_cycle_6_end_BRK6E.value = 0
    await Timer(1, unit="ns")
    assert dut.interrupt_disable_I_OUT.value == 1, "I didn't stay set after BRK6E"
    assert dut.register_data.value == 0b0000_0100
