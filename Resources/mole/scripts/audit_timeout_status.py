#!/usr/bin/env python3
"""Reject raw comparisons against the timeout status 124.

run_with_timeout reports 124 for a timeout and 128+N for a signal. Whether a
caller must stop the run or only skip one item is its own contract, and
spelling the numbers by hand is how the wrong one kept shipping. Callers use
mole_rc_timeout or mole_rc_timeout_or_signal from lib/core/timeout.sh instead;
that file is the only place allowed to compare against 124. Producing the
status (`return 124`, `exit 124`) is fine.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
ALLOWED = {PROJECT_ROOT / "lib" / "core" / "timeout.sh"}
COMPARISON = re.compile(
    r"(?:-eq|-ne|==|!=)\s*[\"']?124\b"
    r"|\b124\s*(?:-eq|-ne|==|!=)"
    r"|^\s*[\"']?124[\"']?\s*\)"
)


def default_sources() -> list[Path]:
    sources = [PROJECT_ROOT / "mole"]
    for directory in ("bin", "lib", "scripts"):
        sources.extend((PROJECT_ROOT / directory).rglob("*.sh"))
    return sorted({path.resolve() for path in sources if path.is_file()} - ALLOWED)


def inspect_file(path: Path) -> list[int]:
    findings: list[int] = []
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if line.lstrip().startswith("#"):
            continue
        if COMPARISON.search(line):
            findings.append(number)
    return findings


def main(argv: list[str]) -> int:
    sources = [Path(arg).resolve() for arg in argv] if argv else default_sources()
    findings = [(source, line) for source in sources for line in inspect_file(source)]
    if findings:
        for source, line in findings:
            print(f"{source}:{line}: compare timeout statuses with mole_rc_timeout or mole_rc_timeout_or_signal")
        return 1
    print(f"timeout-status-audit-ok files={len(sources)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
