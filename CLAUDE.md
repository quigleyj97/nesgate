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
./formal                    # analyze every core, then run each core's SymbiYosys proofs
```

`synth` wipes `build/`, runs `ruff check .`, runs every core's `./analyze $BUILD_DIR`, then every core's `./test $BASE_DIR`, and merges the cocotb `results.xml` files into `build/results.json` (CTRF format, consumed by CI). Then it runs `pyright`, which needs the DUT stubs the tests just wrote. Ruff (`ruff.toml`) and Pyright (`pyrightconfig.json`) use the same configs as the Ruff and Pylance VS Code extensions. It then runs every core's `./check $BUILD_DIR`, which fails the build if any entity doesn't compile or doesn't synthesize on its own (e.g. an inferred latch), even if the toplevel doesn't use it yet. Finally it synthesizes `targets/ulx3s_85k.vhdl`; Yosys flattens the design, merges each shared `'Z'` bus's drivers with `tribuf -merge`, and maps every tri-state buffer with `techmaps/precharge_tribuf.v` (see `techmaps/index.md`) into a mux that reads all ones while nothing drives it (the precharge), and treats `conflicting drivers` warnings as errors. The output is `build/toplevel.ulx3s.bit`. Any tool missing from PATH falls back to an amd64 `hdlc/*` Docker image.

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
  - `formal` (optional): a `PROOFS` list of `<entity>:<sby file>` pairs, passed to `util/formal_check`. It synthesizes each entity from the build library to `build/formal/<entity>.v` with `ghdl --synth --out=verilog` (SymbiYosys can't read VHDL with the open source toolchain), then runs every task in the `.sby` file from inside `build/`. So `.sby` `[files]` paths are relative to `build/`, like `analyze` (`formal/<entity>.v`, `../cores/...`). The SystemVerilog property harnesses live next to the subunit, in a `formal/` directory. The top-level `./formal` clears `build/formal/`, analyzes every core, then runs each core's `formal $BUILD_DIR`. CI runs it as a separate job and uploads `build/formal/`.
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
- **Buses.** The real buses are precharged-high wired-AND nodes, which `'Z'` drivers on a shared signal can't model, so leaf entities never share an `inout` bus. Instead:
  - A leaf that drives a bus has an `out std_ulogic_vector` port that is `'Z'` when not enabled. Every bit needs a driver, or it defaults to `'U'` and corrupts the bus.
  - For synthesis, drive the whole port with one conditional assignment (`value when enable else (others => 'Z')`): yosys only merges tri-state drivers of a bus that cover the same bits, and the rest become conflicting drivers. A bit that's never driven goes inside that assignment (a constant `'Z'` doesn't survive synthesis), and an input that's never driven gets all ones, which reads the same as `'Z'` on a precharged bus.
  - A leaf that reads a bus has a separate `in` port, suffixed `_in` (e.g. `bus_ADL_in`/`bus_ADL_out`).
  - In `mos_6502_datapath`, every leaf drives a per-bus `drivers_*` signal. It has several drivers, so it must be a resolved `std_logic_vector`: an unresolved `std_ulogic_vector` with several drivers elaborates and synthesizes, but fails at simulation time. Convert at the port map, e.g. `std_logic_vector(data_out) => drivers_SB`.
  - `bus_multiplexer` resolves the drivers into the `bus_*` values every leaf reads: undriven bits read `'1'` (precharge), any `'0'` wins (open drain and wired-AND), and `SB/DB`/`SB/ADH` merge the buses they connect (pass MOSFETs). Drivers outside the datapath (e.g. the ALU) come in through the datapath's `drive_*` ports, which feed the multiplexer's `external_*` inputs separately, since GHDL can't synthesize a plain assignment merged with tri-state drivers.
  - Leaf testbenches check for high impedance on a drive port with `not dut.<sig>.value.is_resolvable`. Datapath testbenches drive buses through `drive_*` (`LogicArray("ZZZZZZZZ")` to release), and an idle bus reads `0xFF`.
- Use `std_ulogic`/`std_ulogic_vector`.
- **Docs** are Doxygen. Use `--!` comments in VHDL (`@file`, `@brief`, `@details`) and `{#anchor}` / `@subpage` / `@ref` in markdown. CI publishes them to GitHub Pages.
