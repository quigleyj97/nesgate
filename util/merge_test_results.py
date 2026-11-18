import sys
from xml.etree import ElementTree as ET

from cocotb import __version__ as cocotb_version

from util.ctrf import write_ctrf


def read_results(start_ts: int, stop_ts: int, files: list[str]):
    tests = []
    for file in files:
        with open(file, 'r') as file_handle:
            document = ET.parse(file_handle)
            for test in document.findall('.//testcase'):
                test_details = dict(test.items())
                # Copra's stub generator runs as a test; it isn't one of ours.
                if test_details["classname"].startswith("copra."):
                    continue
                has_failure = test.find("failure") is not None
                result = {
                    "name": test_details["name"],
                    "status": "passed" if not has_failure else "failed",
                    "duration": test_details["time"],
                    "suite": test_details["classname"],
                }
                tests.append(result)
    write_ctrf(
        './build/results.json',
        {"name": "cocotb", "version": cocotb_version},
        start_ts,
        stop_ts,
        tests,
    )

if __name__ == "__main__":
    read_results(int(sys.argv[1]), int(sys.argv[2]), sys.argv[3:])
