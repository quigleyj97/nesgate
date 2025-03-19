import sys
import os
from pathlib import Path
from cocotb.runner import get_runner

sim = os.getenv("SIM", "ghdl")
root_path = Path(__file__).resolve().parent.parent

def run_cocotb_test(toplevel_name: str, test_name: str, sources: list[str]):
    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel=toplevel_name,
        build_dir=root_path / "build" / toplevel_name / test_name
    )

    runner.test(
        hdl_toplevel=toplevel_name,
        test_module=test_name,
        plusargs=mk_plusargs(toplevel_name)
    )

def mk_plusargs(test_name: str) -> list[str]:
    plusargs = []
    waveform_file = os.getenv("WAVE")
    if waveform_file is not None:
        plusargs.append("--vcd=" + ".".join([test_name, "vcd"]))
    return plusargs

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python run_cocotb.py <toplevel_name> <test_name> <source_files...>")
        sys.exit(1)
    run_cocotb_test(sys.argv[1], sys.argv[2], sys.argv[3:])