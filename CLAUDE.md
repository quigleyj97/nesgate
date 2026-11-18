# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

NESgate is a VHDL implementation of the NES, targeting the ULX3S (ECP5-85k) FPGA board. Work so far is the Ricoh 2A03 / MOS 6502 CPU (`cores/ricoh_2A03`), modeled closely on the real chip's transistor-level structure (buses, pass/precharge MOSFETs, named decoder control signals) and not as a behavioral CPU.

## Toolchain and commands

You need OSS CAD Suite (GHDL, Yosys, nextpnr-ecp5, ecppack). Use the release pinned in `.github/actions/setup-oss-cad-suite/action.yml` (shared by the CI workflows). You also need Python 3.12 with pipenv. `mise.toml` sets `PIPENV_IGNORE_VIRTUALENVS=1`, which is needed on macOS because the suite's `environment` script hijacks `VIRTUAL_ENV`.

```
source /path/to/oss-cad-suite/environment
pipenv install --dev
pipenv run ./synth          # lint, analyze + test + type-check every core, then synthesize the bitstream
./formal                    # analyze every core, then run each core's SymbiYosys proofs
```

`synth` wipes `build/`, runs `ruff check .`, runs every core's `./analyze $BUILD_DIR`, then every core's `./test $BASE_DIR`, and merges the cocotb `results.xml` files into `build/results.json` (CTRF format, consumed by CI). Then it runs `pyright`, which needs the DUT stubs the tests just wrote. Ruff (`ruff.toml`) and Pyright (`pyrightconfig.json`) use the same configs as the Ruff and Pylance VS Code extensions. It then runs every core's `./check $BUILD_DIR`, which fails the build if any entity doesn't compile or doesn't synthesize on its own (e.g. an inferred latch), even if the toplevel doesn't use it yet. Finally it synthesizes `targets/ulx3s_85k.vhdl` with `synth_ecp5`, treating `conflicting drivers` warnings as errors (the design has no tri-states, so a signal with several drivers is always a bug). The output is `build/toplevel.ulx3s.bit`. Any tool missing from PATH falls back to an amd64 `hdlc/*` Docker image.

Run a single testbench from the repo root (GHDL must be on PATH):

```
pipenv run python -m util.run_cocotb <toplevel_entity> <python.test.module> <vhdl sources...>
# e.g.
pipenv run python -m util.run_cocotb bus_multiplexer cores.ricoh_2A03.datapath.verify_bus_multiplexer ./cores/ricoh_2A03/datapath/bus_multiplexer.vhdl
```

Set `WAVE=1` to dump a VCD. With the dev packages installed, every testbench run also writes a DUT type stub to `typings/<toplevel_entity>.pyi` with [Copra](https://github.com/cocotb/copra), for Pylance and Pyright; set `COPRA=0` to skip it. `typings/` is gitignored, so on a fresh clone run the tests once (e.g. `pipenv run ./synth`) before the editor can type `dut`. `util/copra_stubs.py` restores the VHDL source casing that GHDL lowercases. Each testbench builds into `build/<toplevel_entity>/`. The simulator defaults to GHDL and can be overridden with `SIM`.

cocotb is pinned to `~=2.1`. Use the 2.x API: `cocotb_tools.runner`, `cocotb.types.LogicArray` (not `BinaryValue`), `unit=` (not `units=`), `str(value)` (not `.binstr`), and `cocotb.start_soon`.

## Structure

- `cores/<name>/`: self-contained cores. Each one has:
  - `analyze`: runs `$GHDL -i` on the core's VHDL files from inside `build/`, using paths like `../cores/...`. GHDL's `work-obj*.cf` records these *input* paths, and top-level elaboration in `build/` depends on them, so keep that path style.
  - `test`: one `python -m util.run_cocotb ...` line per testbench, run from the repo root (`$1`).
  - `check`: an `ENTITIES` list of every entity in the core, passed to `util/synth_check`, which runs `ghdl -m -b` and `ghdl --synth` on each one.
  - `formal` (optional): a `PROOFS` list of `<entity>:<sby file>` pairs, passed to `util/formal_check`. It synthesizes each entity from the build library to `build/formal/<entity>.v` with `ghdl --synth --out=verilog` (SymbiYosys can't read VHDL with the open source toolchain), then runs every task in the `.sby` file from inside `build/`. So `.sby` `[files]` paths are relative to `build/`, like `analyze` (`formal/<entity>.v`, `../cores/...`). GHDL elaborates generics away, so a generic entity lists variants after the `.sby` file (`<entity>:<sby file>:divide_by=2:divide_by=7`, several generics comma-separated). Each variant goes to its own netlist instead (`formal/<entity>_divide_by_7.v`), and the `.sby` file reads each one in its own task and sets the harness parameter to match with `chparam` (see `cores/clock_divider/proofs/`). A harness that wires several entities together lists them joined by `+` (`predecode_register+decoder_rom:<sby file>`), and each one goes to its own netlist (see `cores/ricoh_2A03/decoder/proofs/decoder.sby`). The SystemVerilog property harnesses and `.sby` files live next to the entity they verify, in a `proofs/` directory (not `formal/`, which would clash with the hook script in a core whose entity sits at its root). The top-level `./formal` clears `build/formal/`, analyzes every core, then runs each core's `formal $BUILD_DIR`. CI runs it in its own workflow (`.github/workflows/formal.yml`) and uploads `build/formal/`. Yosys pitfalls in harnesses: a `case` on a value becomes a ROM whose contents k-induction leaves free (use a bit table, as in `predecode_logic_formal.sv`); a variable part-select (`v[i*12 +: 12]`) leaves `x` bits that `abc pdr` rejects (shift instead); and labels inside a `generate` loop aren't uniquified, so write each named assertion out.
  - `__init__.py` plus `verify_<entity>.py` cocotb testbenches, one per entity.
- `cores/ricoh_2A03/` is split into `alu/`, `datapath/` and `decoder/`. `alu/logic_core.vhdl` and `datapath/mos_6502_datapath.vhdl` wire their subunits together. (Don't name them `core.vhdl`: GHDL's LLVM backend names object files after the source file, so two `core.vhdl` files in one testbench collide at link time.) The CPU entity is `mos_6502` in `cores/ricoh_2A03/core.vhdl`, which wires the decoder, ALU and datapath together. `verify_mos_6502.py` tests the whole CPU end to end, using `harness.py`: it drives Phi1/Phi2, models 64 KiB of memory on the pins, and records each bus cycle, so tests can check a program's exact bus trace or the values it stores. `notes/` holds design notes: clocks, the bus/datapath layout, and the decoder control signals, grouped by the part of the CPU they control.
- `targets/ulx3s_85k.vhdl` is the synthesis top level (`toplevel`). It declares components inline and binds them with `for ... use entity work.<entity>`. `targets/ulx3s.lpf` holds the pin constraints.
- `util/run_cocotb.py` wraps the cocotb runner. `util/merge_test_results.py` produces the CTRF report.

### Adding a new entity to a core

1. Add the VHDL file to that core's `analyze` `FILES` list.
2. Add a `verify_<entity>.py` testbench and a matching line in the core's `test` script. Run it once to generate its stub, then annotate the testbench's `dut` with it (`if TYPE_CHECKING: from <entity> import <Entity> as DUT`, then `dut: "DUT"`).
3. Add the entity to the core's `check` `ENTITIES` list.
4. Update the Doxygen docs: the subunit's `index.md` and the checklist in `cores/ricoh_2A03/notes/organization.md`.

## Design conventions

- **Metaclock.** Real 6502 registers are clocked by multiple control signals and phases, which yosys can't synthesize. Sequential components therefore take an extra `metaclock` input (a fast clock not present on real hardware) and sample their load/control signals on its edge. Sample the load signal's *level* (`if rising_edge(metaclock) then if load = '1' ...`), like the real transparent latches, rather than loading on the load signal's own edge: a bus often starts being driven at the same moment its load signal rises, so an edge-triggered register latches the stale value. See `cores/ricoh_2A03/notes/clocks.md`. `phi1`/`phi2` are the 6502's two-phase clocks, generated by `cores/phased_clock_generator`.
- **Signal naming.** Ports combine a descriptive name with the original 6502 control signal mnemonic, e.g. `load_SB_ADD` for `SB/ADD` and `enable_sum_SUMS` for `SUMS`. Follow the naming in `notes/signals.md`.
- **Buses.** The real buses are precharged-high wired-AND nodes: when several drivers are enabled at once, the bus reads their AND, and unofficial opcodes like SBX rely on it. `'Z'` drivers can't model that (GHDL resolves `'0'` against `'1'` to `'X'`, `tribuf -merge` builds a mux that ORs them, and `ghdl --synth` ignores custom resolution functions), so the design has no tri-states and no shared `inout` buses. Instead:
  - A leaf that drives a bus has an `out std_ulogic_vector` port that drives all ones (released) when not enabled: `value when enable = '1' else (others => '1')`. Every bit needs a driver, or it defaults to `'U'` and corrupts the bus. Never use `'Z'`: the bus multiplexer turns a stray `'Z'` into `'X'` in simulation.
  - A leaf that reads a bus has a separate `in` port, suffixed `_in` (e.g. `bus_ADL_in`/`bus_ADL_out`).
  - In `mos_6502_datapath`, every leaf drives its own signal per bus, named after the control signal (e.g. `AC_DB`, `PCL_ADL`), and each bus's `drivers_*` signal is the AND of all of them and the datapath's `drive_*` input. A new driver of a bus has to be added to that AND.
  - `bus_multiplexer` turns the ANDed drivers into the `bus_*` values every leaf reads: it applies the open drain MOSFETs and merges the buses `SB/DB`/`SB/ADH` connect (pass MOSFETs). Drivers outside the datapath (e.g. the ALU) come in through the datapath's `drive_*` ports; an input that nothing drives gets all ones.
  - Testbenches check that a drive port is released with `dut.<sig>.value == 0xFF` (make sure the register doesn't hold 0xFF itself). Datapath testbenches drive buses through `drive_*` (`0xFF` to release), and an idle bus reads `0xFF`.
- Use `std_ulogic`/`std_ulogic_vector`.
- **Docs** are Doxygen. Use `--!` comments in VHDL (`@file`, `@brief`, `@details`) and `{#anchor}` / `@subpage` / `@ref` in markdown. CI publishes them to GitHub Pages.
