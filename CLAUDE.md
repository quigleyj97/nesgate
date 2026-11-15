# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

NESgate is a VHDL implementation of the NES, targeting the ULX3S (ECP5-85k) FPGA board. Work so far is the Ricoh 2A03 / MOS 6502 CPU (`cores/ricoh_2A03`), modeled closely on the real chip's transistor-level structure (buses, pass/precharge MOSFETs, named decoder control signals) and not as a behavioral CPU.

## Toolchain and commands

You need OSS CAD Suite (GHDL, Yosys, nextpnr-ecp5, ecppack). Use the release pinned in `.github/workflows/synthesize.yml`. You also need Python 3.12 with pipenv. `mise.toml` sets `PIPENV_IGNORE_VIRTUALENVS=1`, which is needed on macOS because the suite's `environment` script hijacks `VIRTUAL_ENV`.

```
source /path/to/oss-cad-suite/environment
pipenv install --dev
pipenv run ./synth          # lint, analyze + test + type-check every core, then synthesize the bitstream
```

`synth` wipes `build/`, runs `ruff check .`, runs every core's `./analyze $BUILD_DIR`, then every core's `./test $BASE_DIR`, and merges the cocotb `results.xml` files into `build/results.json` (CTRF format, consumed by CI). Then it runs `pyright`, which needs the DUT stubs the tests just wrote. Ruff (`ruff.toml`) and Pyright (`pyrightconfig.json`) use the same configs as the Ruff and Pylance VS Code extensions. It then runs every core's `./check $BUILD_DIR`, which fails the build if any entity doesn't compile or doesn't synthesize on its own (e.g. an inferred latch), even if the toplevel doesn't use it yet. Finally it synthesizes `targets/ulx3s_85k.vhdl`; Yosys flattens the design and runs `tribuf -logic` so the shared `'Z'` buses become muxes, and treats `conflicting drivers` warnings as errors. The output is `build/toplevel.ulx3s.bit`. Any tool missing from PATH falls back to an amd64 `hdlc/*` Docker image.

Run a single testbench from the repo root (GHDL must be on PATH):

```
pipenv run python -m util.run_cocotb <toplevel_entity> <python.test.module> <vhdl sources...>
# e.g.
pipenv run python -m util.run_cocotb pass_mosfet cores.ricoh_2A03.datapath.verify_pass_mosfet ./cores/ricoh_2A03/datapath/pass_mosfet.vhdl
```

Set `WAVE=1` to dump a VCD. With the dev packages installed, every testbench run also writes a DUT type stub to `typings/<toplevel_entity>.pyi` with [Copra](https://github.com/cocotb/copra), for Pylance and Pyright; set `COPRA=0` to skip it. `typings/` is gitignored, so on a fresh clone run the tests once (e.g. `pipenv run ./synth`) before the editor can type `dut`. `util/copra_stubs.py` restores the VHDL source casing that GHDL lowercases. Each testbench builds into `build/<toplevel_entity>/`. The simulator defaults to GHDL and can be overridden with `SIM`.

cocotb is pinned to `~=2.1`. Use the 2.x API: `cocotb_tools.runner`, `cocotb.types.LogicArray` (not `BinaryValue`), `unit=` (not `units=`), `str(value)` (not `.binstr`), and `cocotb.start_soon`.

## Structure

- `cores/<name>/`: self-contained cores. Each one has:
  - `analyze`: runs `$GHDL -i` on the core's VHDL files from inside `build/`, using paths like `../cores/...`. GHDL's `work-obj*.cf` records these *input* paths, and top-level elaboration in `build/` depends on them, so keep that path style.
  - `test`: one `python -m util.run_cocotb ...` line per testbench, run from the repo root (`$1`).
  - `check`: an `ENTITIES` list of every entity in the core, passed to `util/synth_check`, which runs `ghdl -m -b` and `ghdl --synth` on each one.
  - `__init__.py` plus `verify_<entity>.py` cocotb testbenches, one per entity.
- `cores/ricoh_2A03/` is split into `alu/` and `datapath/`, each with its own `core.vhdl` wiring the subunits together. The CPU entity is `mos_6502` in `cores/ricoh_2A03/core.vhdl`. `notes/` holds design notes: clocks, the bus/datapath layout, and the decoder control signals, grouped by the part of the CPU they control.
- `targets/ulx3s_85k.vhdl` is the synthesis top level (`toplevel`). It declares components inline and binds them with `for ... use entity work.<entity>`. `targets/ulx3s.lpf` holds the pin constraints.
- `util/run_cocotb.py` wraps the cocotb runner. `util/merge_test_results.py` produces the CTRF report.

### Adding a new entity to a core

1. Add the VHDL file to that core's `analyze` `FILES` list.
2. Add a `verify_<entity>.py` testbench and a matching line in the core's `test` script. Run it once to generate its stub, then annotate the testbench's `dut` with it (`if TYPE_CHECKING: from <entity> import <Entity> as DUT`, then `dut: "DUT"`).
3. Add the entity to the core's `check` `ENTITIES` list.
4. Update the Doxygen docs: the subunit's `index.md` and the checklist in `cores/ricoh_2A03/notes/organization.md`.

## Design conventions

- **Metaclock.** Real 6502 registers are clocked by multiple control signals and phases, which yosys can't synthesize. Sequential components therefore take an extra `metaclock` input (a fast clock not present on real hardware) and sample their load/control signals on its edge. See `cores/ricoh_2A03/notes/clocks.md`. `phi1`/`phi2` are the 6502's two-phase clocks, generated by `cores/phased_clock_generator`.
- **Signal naming.** Ports combine a descriptive name with the original 6502 control signal mnemonic, e.g. `load_SB_ADD` for `SB/ADD` and `enable_sum_SUMS` for `SUMS`. Follow the naming in `notes/signals.md`.
- **Buses** are `inout std_ulogic_vector` ports on leaf entities, with `'Z'` when not driven. Every bit of an `inout` bus port needs a driver (`'Z'` if it's never driven), or it defaults to `'U'` and corrupts the bus. A *signal* or port shared by more than one driver must be a resolved `std_logic_vector`: an unresolved `std_ulogic_vector` with several drivers elaborates and synthesizes, but fails at simulation time. Convert at the port map, e.g. `std_logic_vector(data_out) => databus_SB` (see `mos_6502_datapath`). Pass/precharge/open-drain MOSFETs are modeled as separate entities. Testbenches check for high impedance with `not dut.<sig>.value.is_resolvable`.
- Use `std_ulogic`/`std_ulogic_vector`.
- **Docs** are Doxygen. Use `--!` comments in VHDL (`@file`, `@brief`, `@details`) and `{#anchor}` / `@subpage` / `@ref` in markdown. CI publishes them to GitHub Pages.
