"""Write test results as a CTRF report, for ctrf-io/github-test-reporter.

Standard library only, so jobs without the pipenv environment can use it.
"""

import json
from collections import Counter
from datetime import datetime
from typing import Any
from uuid import uuid4

STATUSES = ("passed", "failed", "pending", "skipped", "other")


def write_ctrf(
    path: str,
    tool: dict[str, str],
    start_ts: int,
    stop_ts: int,
    tests: list[dict[str, Any]],
) -> None:
    """Write `tests` (CTRF test objects with at least `name` and `status`) to
    `path`, with a summary counted from their statuses."""
    counts = Counter(test["status"] for test in tests)
    ctrf = {
        "reportFormat": "ctrf",
        "specVersion": "0.0.0",
        "reportId": str(uuid4()),
        "timestamp": datetime.now().isoformat(),
        "generatedBy": "nesgate",
        "results": {
            "tool": tool,
            "summary": {
                "tests": len(tests),
                **{status: counts[status] for status in STATUSES},
                "start": start_ts,
                "stop": stop_ts,
            },
            "tests": tests,
        },
    }
    with open(path, "w") as f:
        json.dump(ctrf, f)
