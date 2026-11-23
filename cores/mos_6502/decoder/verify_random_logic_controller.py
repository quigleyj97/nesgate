import os
from typing import TYPE_CHECKING, Any

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles
from cocotb.types import LogicArray

from cores.mos_6502.decoder.verify_decoder_rom import expected

if TYPE_CHECKING:
    from random_logic_controller import RandomLogicController as DUT

METACLOCKS_PER_PHASE = 4

OUTPUTS = [
    "reset_short_counter_TRES1",
    "reset_counters_TRESX",
    "shift_instruction_SHIFT",
    "memory_operation_MemOP",
    "store_cycle_STOR",
    "pc_to_db_PC_DB",
    "fetch_opcode_FETCH",
    "inject_brk_0_IR",
    "output_enable_X_SB",
    "output_enable_Y_SB",
    "load_SB_X",
    "load_SB_Y",
    "output_enable_S_SB",
    "output_enable_S_ADL",
    "load_SB_S",
    "refresh_S_S",
    "load_NDB_ADD",
    "load_DB_ADD",
    "load_ADL_ADD",
    "load_SB_ADD",
    "load_0_ADD",
    "enable_ands_ANDS",
    "enable_eors_EORS",
    "enable_ors_ORS",
    "enable_srs_SRS",
    "enable_sums_SUMS",
    "carry_in_I_ADDC",
    "decimal_add_DAA",
    "decimal_subtract_DSA",
    "output_enable_ADD_SB_0_6",
    "output_enable_ADD_SB_7",
    "output_enable_ADD_ADL",
    "load_SB_AC",
    "output_enable_AC_SB",
    "output_enable_AC_DB",
    "increment_pc_I_PC",
    "load_PCL_PCL",
    "load_ADL_PCL",
    "output_enable_PCL_ADL",
    "output_enable_PCL_DB",
    "load_PCH_PCH",
    "load_ADH_PCH",
    "output_enable_PCH_ADH",
    "output_enable_PCH_DB",
    "load_ADH_ABH",
    "load_ADL_ABL",
    "connect_SB_DB",
    "connect_SB_ADH",
    "clear_0_ADH0",
    "clear_0_ADH_1_7",
    "output_enable_DL_DB",
    "output_enable_DL_ADL",
    "output_enable_DL_ADH",
    "output_enable_P_DB",
    "load_DB0_C",
    "load_IR5_C",
    "load_ACR_C",
    "load_DB1_Z",
    "load_DBZ_Z",
    "load_DB2_I",
    "load_IR5_I",
    "load_DB3_D",
    "load_IR5_D",
    "load_DB6_V",
    "load_AVR_V",
    "clear_0_V",
    "load_DB7_N",
]

# Inputs other than the decoder lines and cycle signals, with their idle values
DEFAULTS = {
    "ready": 1,
    "ready_phi1_ReadyPhi1": 1,
    "single_byte_IMPLIED": 0,
    "reset_pending_RESP": 0,
    "brk_cycle_6_end_BRK6E": 0,
    "break_flag_B_OUT": 1,
    "vector_0_ADL0": 0,
    "alu_carry_ACR": 0,
    "carry_flag_C_OUT": 0,
    "decimal_flag_D_OUT": 0,
    "overflow_flag_V_OUT": 0,
    "negative_flag_N_OUT": 0,
    "zero_flag_Z_OUT": 0,
}

Outputs = dict[str, int]

NOP = 0xEA


def outputs(dut: "DUT") -> Outputs:
    return {name: int(getattr(dut, name).value) for name in OUTPUTS}


def asserted(state: Outputs) -> set[str]:
    return {name for name, value in state.items() if value}


async def cycle(
    dut: "DUT",
    opcode: int = NOP,
    cycles: frozenset[str] | set[str] = frozenset(),
    *,
    t0: int | None = None,
    t1: int | None = None,
    t6: int = 0,
    t7: int = 0,
    db7: int = 0,
    **inputs: int,
) -> tuple[Outputs, Outputs]:
    """Run one CPU cycle (Phi1 then Phi2), with the decoder lines for `opcode`
    in `cycles` (names as in the decoder ROM testbench) held throughout.

    `T0` and `T1` default to whether `cycles` has `T0` and `T1X`. Other inputs
    are passed by port name, and default to `DEFAULTS`.

    Returns the outputs at the end of Phi1, and after Phi2. The output latches
    load during Phi2, so the second is what drives the datapath during the next
    Phi1.
    """
    unknown = set(inputs) - set(DEFAULTS)
    assert not unknown, f"Unknown inputs {unknown}"
    lines = expected(opcode, set(cycles))
    dut.decoder_in.value = LogicArray.from_unsigned(sum(1 << n for n in lines), 130)
    dut.instruction_IR5.value = opcode >> 5 & 1
    dut.cycle_T0.value = int("T0" in cycles) if t0 is None else t0
    dut.cycle_T1.value = int("T1X" in cycles) if t1 is None else t1
    dut.rmw_cycle_T6.value = t6
    dut.rmw_cycle_T7.value = t7
    dut.bus_DB_in.value = LogicArray.from_unsigned(db7 << 7 | 0x7F, 8)
    for name, default in DEFAULTS.items():
        getattr(dut, name).value = inputs.get(name, default)

    dut.phi1.value = 1
    await ClockCycles(dut.metaclock, METACLOCKS_PER_PHASE)
    dut.phi1.value = 0
    await ClockCycles(dut.metaclock, 1)
    during_phi1 = outputs(dut)

    dut.phi2.value = 1
    await ClockCycles(dut.metaclock, METACLOCKS_PER_PHASE)
    dut.phi2.value = 0
    await ClockCycles(dut.metaclock, 1)
    after_phi2 = outputs(dut)
    return during_phi1, after_phi2


async def start(dut: "DUT"):
    """Start the metaclock and run idle cycles until every latch has settled."""
    cocotb.start_soon(Clock(dut.metaclock, 1, unit="ns").start())
    dut.phi1.value = 0
    dut.phi2.value = 0
    for _ in range(4):
        await cycle(dut)


def check(
    state: Outputs,
    on: set[str],
    off: set[str] | frozenset[str] = frozenset(),
    what: str = "",
):
    missing = {name for name in on if not state[name]}
    extra = {name for name in off if state[name]}
    assert not missing and not extra, (
        f"{what}: expected {sorted(missing)} to be set, {sorted(extra)} to be clear"
    )


# Commands driven by T0 of every instruction, to fetch the next opcode
FETCH_ADDRESS = {
    "output_enable_PCL_ADL",
    "output_enable_PCH_ADH",
    "load_ADL_PCL",
    "load_ADH_PCH",
    "load_ADL_ABL",
    "load_ADH_ABH",
}


@cocotb.test()
async def test_lda_immediate(dut: "DUT"):
    """LDA #: at T0 the operand goes DL -> DB -> SB -> AC, sets N and Z, and the
    next opcode is fetched from PC. The instruction ends (TRES1)."""
    await start(dut)
    _, after = await cycle(dut, 0xA9, {"T0", "T2"})
    check(
        after,
        {
            "load_SB_AC",
            "connect_SB_DB",
            "output_enable_DL_DB",
            "load_DBZ_Z",
            "load_DB7_N",
            "reset_short_counter_TRES1",
            *FETCH_ADDRESS,
        },
        {
            "load_SB_X",
            "load_SB_Y",
            "output_enable_AC_SB",
            "load_PCL_PCL",
            "load_PCH_PCH",
        },
        "LDA # T0",
    )


@cocotb.test()
async def test_transfers(dut: "DUT"):
    """TAX, TXS and LDX # move registers over SB."""
    await start(dut)
    _, after = await cycle(dut, 0xAA, {"T0", "T2"})
    check(
        after,
        {"output_enable_AC_SB", "load_SB_X", "load_DBZ_Z", "load_DB7_N", "refresh_S_S"},
        {"load_SB_AC", "load_SB_S", "load_SB_Y"},
        "TAX",
    )
    _, after = await cycle(dut, 0x9A, {"T0", "T2"})
    check(
        after,
        {"output_enable_X_SB", "load_SB_S"},
        {"refresh_S_S", "load_SB_X", "load_DBZ_Z"},
        "TXS",
    )
    _, after = await cycle(dut, 0xA2, {"T0", "T2"})
    check(
        after,
        {"load_SB_X", "output_enable_DL_DB", "connect_SB_DB", "load_DBZ_Z"},
        {"load_SB_AC", "output_enable_AC_SB"},
        "LDX #",
    )


@cocotb.test()
async def test_sta_zero_page(dut: "DUT"):
    """STA zpg: at T2 the operand addresses page 0, and the store finishes at
    T0 with A on DB."""
    await start(dut)
    phi1, after = await cycle(dut, 0x85, {"T2"})
    assert phi1["store_cycle_STOR"], "STOR at T2"
    assert phi1["memory_operation_MemOP"], "MemOP at T2"
    check(
        after,
        {
            "output_enable_DL_ADL",
            "clear_0_ADH0",
            "clear_0_ADH_1_7",
            "load_ADL_ABL",
            "load_ADH_ABH",
            "output_enable_AC_DB",
            "reset_counters_TRESX",
        },
        {"output_enable_PCL_ADL", "output_enable_PCH_ADH", "load_SB_AC"},
        "STA zpg T2",
    )


@cocotb.test()
async def test_long_instruction_completion(dut: "DUT"):
    """LDA abs finishes after its memory cycle (T3). INC abs doesn't: it's a
    read-modify-write instruction, which finishes at T7."""
    await start(dut)
    _, after = await cycle(dut, 0xAD, {"T2"})
    check(
        after,
        {"output_enable_PCL_ADL", "output_enable_PCH_ADH"},
        {"reset_counters_TRESX"},
        "LDA abs T2",
    )
    _, after = await cycle(dut, 0xAD, {"T3"})
    check(
        after,
        {"reset_counters_TRESX", "output_enable_DL_ADH", "output_enable_ADD_ADL"},
        {"output_enable_PCH_ADH"},
        "LDA abs T3",
    )

    _, after = await cycle(dut, 0xEE, {"T3"})
    assert not after["reset_counters_TRESX"], "INC abs ended at T3"
    phi1, _ = await cycle(dut, 0xEE, set(), t6=1)
    assert phi1["shift_instruction_SHIFT"]
    _, after = await cycle(dut, 0xEE, set(), t7=1)
    assert after["reset_counters_TRESX"], "INC abs didn't end at T7"


@cocotb.test()
async def test_opcode_fetch(dut: "DUT"):
    """FETCH follows T1, and 0/IR injects BRK unless fetching without an
    interrupt pending."""
    await start(dut)
    _, after = await cycle(dut, t1=1)
    check(after, {"fetch_opcode_FETCH"}, {"inject_brk_0_IR"}, "T1")
    _, after = await cycle(dut)
    check(after, {"inject_brk_0_IR"}, {"fetch_opcode_FETCH"}, "outside T1")
    _, after = await cycle(dut, t1=1, break_flag_B_OUT=0)
    check(after, {"fetch_opcode_FETCH", "inject_brk_0_IR"}, set(), "T1, interrupt")


@cocotb.test()
async def test_pc_increment(dut: "DUT"):
    """PC increments after the opcode fetch, except for single-byte opcodes and
    interrupts."""
    await start(dut)
    for implied, b_out, want in ((0, 1, 1), (1, 1, 0), (0, 0, 0)):
        await cycle(dut, t1=1, break_flag_B_OUT=b_out)
        phi1, _ = await cycle(
            dut, 0xAD, {"T2"}, single_byte_IMPLIED=implied, break_flag_B_OUT=b_out
        )
        assert phi1["increment_pc_I_PC"] == want, (
            f"IMPLIED={implied} B_OUT={b_out}: I/PC={phi1['increment_pc_I_PC']}"
        )


@cocotb.test()
async def test_branch_not_taken(dut: "DUT"):
    """A branch that isn't taken ends at BR2, and increments PC past the
    offset."""
    await start(dut)
    # BNE with Z set: not taken
    _, after = await cycle(dut, 0xD0, {"T2"}, zero_flag_Z_OUT=1)
    assert after["reset_short_counter_TRES1"], "Not taken branch didn't end"
    phi1, _ = await cycle(dut, t1=1)
    assert phi1["increment_pc_I_PC"]
    # BEQ with Z set: taken
    _, after = await cycle(dut, 0xF0, {"T2"}, zero_flag_Z_OUT=1)
    assert not after["reset_short_counter_TRES1"], "Taken branch ended at BR2"
    check(after, {"connect_SB_DB", "output_enable_DL_DB"}, set(), "BR2 taken")


@cocotb.test()
async def test_branch_conditions(dut: "DUT"):
    """IR6 and IR7 pick the flag, and IR5 the value that takes the branch."""
    await start(dut)
    flags = {
        0x10: "negative_flag_N_OUT",
        0x50: "overflow_flag_V_OUT",
        0x90: "carry_flag_C_OUT",
        0xD0: "zero_flag_Z_OUT",
    }
    for base, flag in flags.items():
        for opcode in (base, base | 0x20):
            for value in (0, 1):
                _, after = await cycle(dut, opcode, {"T2"}, **{flag: value})
                taken = value == (opcode >> 5 & 1)
                ended = after["reset_short_counter_TRES1"]
                assert ended != taken, f"{opcode:#04x} with {flag}={value}"


@cocotb.test()
async def test_branch_page_crossing(dut: "DUT"):
    """At BR3 a taken branch ends unless the offset carried PCL into another
    page. If it did, the ALU fixes up PCH: +1 forward, -1 backward."""
    await start(dut)
    for backward, carry, crosses in (
        (0, 0, False),
        (0, 1, True),
        (1, 1, False),
        (1, 0, True),
    ):
        what = f"backward={backward} ACR={carry}"
        await cycle(dut, 0xF0, {"T2"}, zero_flag_Z_OUT=1)
        _, after = await cycle(dut, 0xF0, {"T3"}, db7=backward, alu_carry_ACR=carry)
        assert after["reset_short_counter_TRES1"] != crosses, what
        if crosses:
            # PCH + 1 is ~DB (0x00) + carry; PCH - 1 is DB (0xFF)
            assert after["load_NDB_ADD"] != backward, what
            assert after["load_DB_ADD"] == backward, what
            assert after["connect_SB_ADH"], what
        phi1, _ = await cycle(dut, 0xF0, {"T0"}, alu_carry_ACR=carry)
        if not crosses:
            assert phi1["increment_pc_I_PC"], what
        if crosses:
            assert phi1["carry_in_I_ADDC"] != backward, what
        await cycle(dut, t1=1)


@cocotb.test()
async def test_stall(dut: "DUT"):
    """While not ready, T1 repeats (TRES1), the opcode isn't fetched, and the
    address bus holds."""
    await start(dut)
    _, after = await cycle(dut, t1=1, ready=0)
    check(
        after,
        {"reset_short_counter_TRES1"},
        {"fetch_opcode_FETCH", "load_ADL_ABL", "load_ADH_ABH"},
        "T1 stalled",
    )
    # ORS and 0/ADD hold the ALU output steady. ReadyPhi1 follows ready a
    # cycle later, as the ready controller makes it.
    phi1, after = await cycle(dut, t1=1, ready=0, ready_phi1_ReadyPhi1=0)
    check(after, {"load_0_ADD", "load_ADL_ADD"}, {"load_SB_ADD", "load_NDB_ADD"}, "ALU")
    phi1, _ = await cycle(dut, t1=1, ready_phi1_ReadyPhi1=0)
    assert phi1["enable_ors_ORS"]


@cocotb.test()
async def test_reset(dut: "DUT"):
    """RESP resets the cycle counters."""
    await start(dut)
    _, after = await cycle(dut, 0xAD, {"T2"}, reset_pending_RESP=1)
    check(after, {"reset_counters_TRESX"}, {"reset_short_counter_TRES1"}, "RESP")
    _, after = await cycle(dut)
    _, after = await cycle(dut)
    assert not after["reset_counters_TRESX"]


@cocotb.test()
async def test_jsr_pushes_pc(dut: "DUT"):
    """JSR decodes the PCH push at T3 and the PCL push at T4, so they drive DB
    during the following cycles. Both are writes (PC/DB)."""
    await start(dut)
    _, after = await cycle(dut, 0x20, {"T3"})
    check(
        after,
        {"output_enable_PCH_DB", "pc_to_db_PC_DB"},
        {"output_enable_PCL_DB"},
        "T3",
    )
    phi1, after = await cycle(dut, 0x20, {"T4"})
    assert phi1["pc_to_db_PC_DB"], "PC/DB for the PCL push"
    check(after, {"output_enable_PCL_DB"}, {"output_enable_PCH_DB"}, "T4")


@cocotb.test()
async def test_alu_operations(dut: "DUT"):
    """The ALU operation follows the instruction at T0, a cycle later."""
    await start(dut)
    ops = {
        0x29: "enable_ands_ANDS",
        0x49: "enable_eors_EORS",
        0x09: "enable_ors_ORS",
        0x4A: "enable_srs_SRS",
        0x69: "enable_sums_SUMS",
    }
    for opcode, op in ops.items():
        await cycle(dut, opcode, {"T0", "T2"})
        phi1, _ = await cycle(dut, opcode, {"T1X"})
        on = {name for name in ops.values() if phi1[name]}
        assert on == {op}, f"{opcode:#04x}: {on}"


@cocotb.test()
async def test_carry_and_decimal(dut: "DUT"):
    """ADC adds the C flag as carry-in. With D set, ADC corrects with DAA and
    SBC with DSA, unless decimal_mode is false (the 2A03's cut), which never
    asserts either."""
    decimal_mode = os.environ.get("GENERIC_decimal_mode", "true") == "true"
    await start(dut)
    for opcode, carry, decimal in (
        (0x69, 1, 0),
        (0x69, 0, 1),
        (0xE9, 1, 1),
    ):
        what = f"{opcode:#04x} C={carry} D={decimal}"
        await cycle(
            dut,
            opcode,
            {"T0", "T2"},
            carry_flag_C_OUT=carry,
            decimal_flag_D_OUT=decimal,
        )
        phi1, _ = await cycle(dut, opcode, {"T1X"})
        assert phi1["carry_in_I_ADDC"] == carry, what
        assert phi1["decimal_add_DAA"] == (decimal_mode and decimal and opcode == 0x69), what
        assert phi1["decimal_subtract_DSA"] == (decimal_mode and decimal and opcode == 0xE9), what
        # SBC adds the inverted operand
        assert phi1["load_NDB_ADD"] == (opcode == 0xE9), what


@cocotb.test()
async def test_rotate_right(dut: "DUT"):
    """ROR holds back ADD/SB7 when C was set, so the precharged SB7 shifts the
    carry into bit 7. LSR always drives bit 7."""
    await start(dut)
    for opcode, carry, sb7 in ((0x6A, 1, 0), (0x6A, 0, 1), (0x4A, 1, 1)):
        await cycle(dut, opcode, {"T0", "T2"}, carry_flag_C_OUT=carry)
        _, after = await cycle(dut, opcode, {"T1X"})
        assert after["output_enable_ADD_SB_0_6"]
        assert after["output_enable_ADD_SB_7"] == sb7, f"{opcode:#04x} C={carry}"


@cocotb.test()
async def test_flag_instructions(dut: "DUT"):
    """The flag instructions load the P register from IR5, DB or the ALU."""
    await start(dut)
    cases: list[tuple[int, set[str], set[str], dict[str, Any]]] = [
        (0x18, {"T0", "T2"}, {"load_IR5_C"}, {}),
        (0x78, {"T0", "T2"}, {"load_IR5_I"}, {}),
        (0xD8, {"T0", "T2"}, {"load_IR5_D"}, {}),
        (0xB8, {"T0", "T2"}, {"clear_0_V"}, {}),
        (0x69, {"T1X"}, {"load_AVR_V", "load_ACR_C"}, {}),
        (0x08, {"T2"}, {"output_enable_P_DB"}, {}),
        (
            0x28,
            {"T0"},
            {
                "load_DB0_C",
                "load_DB1_Z",
                "load_DB2_I",
                "load_DB3_D",
                "load_DB6_V",
                "load_DB7_N",
            },
            {},
        ),
        # BIT: N and V from memory at T0, Z from A AND M at T1X
        (0x24, {"T0"}, {"load_DB6_V", "load_DB7_N"}, {}),
        (0x24, {"T1X"}, {"load_DBZ_Z"}, {}),
    ]
    flag_commands = {name for name in OUTPUTS if "_C" in name[-2:]} | {
        "load_IR5_I",
        "load_IR5_D",
        "load_DB1_Z",
        "load_DB2_I",
        "load_DB3_D",
        "load_DB6_V",
        "load_AVR_V",
        "clear_0_V",
        "output_enable_P_DB",
        "load_DB0_C",
    }
    for opcode, cycles, on, inputs in cases:
        _, after = await cycle(dut, opcode, cycles, **inputs)
        check(after, on, flag_commands - on, f"{opcode:#04x} {sorted(cycles)}")
    # BIT T1X doesn't load N from the result
    await cycle(dut, 0x24, {"T0"})
    _, after = await cycle(dut, 0x24, {"T1X"})
    assert not after["load_DB7_N"]


@cocotb.test()
async def test_phi2_cutoff(dut: "DUT"):
    """The register, accumulator, ALU input and PC select commands are cut off
    during Phi2, while the buses precharge. The bus commands aren't."""
    await start(dut)
    _, after = await cycle(dut, 0xA9, {"T0", "T2"})
    assert after["load_SB_AC"] and after["output_enable_DL_DB"]
    dut.phi2.value = 1
    await ClockCycles(dut.metaclock, 1)
    during_phi2 = outputs(dut)
    dut.phi2.value = 0
    await ClockCycles(dut.metaclock, 1)
    check(
        during_phi2,
        {"output_enable_DL_DB", "connect_SB_DB", "output_enable_PCL_ADL"},
        {"load_SB_AC", "load_ADL_PCL", "load_PCL_PCL", "load_SB_ADD", "load_0_ADD"},
        "during Phi2",
    )


@cocotb.test()
async def test_indexed_page_crossing(dut: "DUT"):
    """LDA abs,X ends a cycle early when adding X doesn't carry. With a carry it
    takes the extra cycle to fix up the high byte. Stores always take it."""
    await start(dut)
    for opcode, carry, early in (
        (0xBD, 0, True),
        (0xBD, 1, False),
        (0x9D, 0, False),
    ):
        what = f"{opcode:#04x} ACR={carry}"
        _, after = await cycle(dut, opcode, {"T3"}, alu_carry_ACR=carry)
        assert after["reset_counters_TRESX"] == early, what
        if not early:
            _, after = await cycle(dut, opcode, {"T4"}, alu_carry_ACR=carry)
            assert after["reset_counters_TRESX"], what
        await cycle(dut, opcode, {"T0"})
        await cycle(dut, t1=1)
