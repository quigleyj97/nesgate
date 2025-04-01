from cocotb import __version__ as cocotb_version
from uuid import uuid4
from datetime import datetime
from xml.etree import ElementTree as ET
import json
import sys

def read_results(start_ts: int, stop_ts: int, files: list[str]):
    tests = []
    n_successes = 0
    n_failures = 0
    for file in files:
        with open(file, 'r') as file_handle:
            document = ET.parse(file_handle)
            for test in document.findall('.//testcase'):
                test_details = dict(test.items())
                has_failure = test.find("failure") is not None
                if has_failure:
                    n_failures += 1
                else:
                    n_successes += 1
                result = {
                    "name": test_details["name"],
                    "status": "passed" if not has_failure else "failed",
                    "duration": test_details["time"],
                    "suite": test_details["classname"],
                }
                tests.append(result)
    ctrf = {
        "reportFormat": "ctrf",
        "specVersion": "0.0.0",
        "reportId": str(uuid4()),
        "timestamp": datetime.now().isoformat(),
        "generatedBy": "nesgate",
        "results": {
            "tool": {
                "name": "cocotb",
                "version": cocotb_version
            },
            "summary": {
                "tests": len(tests),
                "passed": n_successes,
                "failed": n_failures,
                "pending": 0,
                "skipped": 0,
                "other": 0,
                "start": start_ts,
                "stop": stop_ts
            },
            "tests": tests
        }
    }
    with open('./build/results.json', 'w') as f:
        json.dump(ctrf, f)

if __name__ == "__main__":
    read_results(int(sys.argv[1]), int(sys.argv[2]), sys.argv[3:])