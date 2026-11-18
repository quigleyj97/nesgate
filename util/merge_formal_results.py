"""Merge SymbiYosys JUnit reports into a CTRF report at build/formal/results.json.

SymbiYosys writes a JUnit report for every task it runs, to
formal/<sby name>_<task>/<sby name>_<task>.xml. Each report is one test suite,
named after the task, with the .sby name as its package. It has a testcase for
the build and one per property; engines that don't report per-property results
(e.g. abc pdr) give a single testcase for the whole task instead. A property
the task's mode doesn't check (asserts in a cover task, covers in a prove task)
is skipped. `formal_check` writes the same kind of report for an entity that
fails to synthesize, since SymbiYosys never runs then.

Standard library only: the formal CI job runs this without pipenv.

Usage: python3 -m util.merge_formal_results <start ts> <stop ts> <xml files...>
"""

import sys
from xml.etree import ElementTree as ET

from util.ctrf import write_ctrf


def testcase_status(testcase: ET.Element) -> str:
    if testcase.find("failure") is not None or testcase.find("error") is not None:
        return "failed"
    if testcase.find("skipped") is not None:
        return "skipped"
    return "passed"


def testcase_message(testcase: ET.Element) -> str | None:
    for tag in ("failure", "error"):
        element = testcase.find(tag)
        if element is not None:
            return element.get("message") or element.get("type") or tag
    return None


def read_results(files: list[str]) -> list[dict[str, object]]:
    tests = []
    for file in files:
        for suite in ET.parse(file).getroot().iter("testsuite"):
            suite_name = f"{suite.get('package')} {suite.get('name')}"
            for testcase in suite.iter("testcase"):
                result: dict[str, object] = {
                    # Properties are named in the harness (e.g. check_carry);
                    # fall back to SymbiYosys's name for the build and for
                    # engines that only report the whole task.
                    "name": testcase.get("id") or testcase.get("name"),
                    "status": testcase_status(testcase),
                    "duration": round(float(testcase.get("time", "0")) * 1000),
                    "suite": suite_name,
                }
                if location := testcase.get("location"):
                    result["filePath"] = location
                if message := testcase_message(testcase):
                    result["message"] = message
                tests.append(result)
    return tests


if __name__ == "__main__":
    write_ctrf(
        "./build/formal/results.json",
        {"name": "SymbiYosys"},
        int(sys.argv[1]),
        int(sys.argv[2]),
        read_results(sys.argv[3:]),
    )
