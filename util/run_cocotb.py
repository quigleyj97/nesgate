import os
import sys
from importlib.util import find_spec
from pathlib import Path

from cocotb_tools.check_results import get_results
from cocotb_tools.runner import get_runner

from util.copra_stubs import restore_casing

sim = os.getenv("SIM", "ghdl")
root_path = Path(__file__).resolve().parent.parent
stub_dir = root_path / "typings"
# Write DUT type stubs (for Pylance and Pyright) whenever Copra, a dev
# dependency, is installed. Set COPRA=0 to opt out.
write_stubs = find_spec("copra") is not None and os.getenv("COPRA") != "0"

def run_cocotb_test(toplevel_name: str, test_name: str, sources: list[str]):
    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel=toplevel_name,
        build_dir=root_path / "build" / toplevel_name
    )

    # Copra's autostub module runs first and writes typings/<toplevel>.pyi.
    test_modules = [test_name]
    extra_env = {}
    stub = stub_dir / f"{toplevel_name}.pyi"
    if write_stubs:
        test_modules.insert(0, "copra.integration.autostub")
        extra_env = {"COPRA_STUB_DIR": str(stub_dir), "COPRA_STUB_FILENAME": stub.name}

    results_xml = runner.test(
        hdl_toplevel=toplevel_name,
        test_module=test_modules,
        plusargs=mk_plusargs(toplevel_name),
        extra_env=extra_env,
    )

    if write_stubs:
        restore_casing(stub, sources)

    # Outside pytest, runner.test() only fails if the simulator does, not if a
    # test does, so check the results here. Otherwise `test` and `synth` carry
    # on with failing tests.
    num_tests, num_failed = get_results(results_xml)
    if num_failed:
        print(f"ERROR: {num_failed} of {num_tests} tests failed in {test_name}", file=sys.stderr)
        sys.exit(1)

def mk_plusargs(test_name: str) -> list[str]:
    plusargs = []
    waveform_file = os.getenv("WAVE")
    if waveform_file is not None:
        plusargs.append("--vcd=" + f"{test_name}.vcd")
    return plusargs

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python run_cocotb.py <toplevel_name> <test_name> <source_files...>")
        sys.exit(1)
    run_cocotb_test(sys.argv[1], sys.argv[2], sys.argv[3:])