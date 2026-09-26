#!/usr/bin/env python3
"""Reject bare [[ ]] assertions that cannot fail a Bats test.

Bats runs test bodies under `set -e`, but bash 3.2, which is /bin/bash on
macOS and what `env bash` resolves to there, does not trigger errexit for a
failing `[[ ]]`. Only the last statement's status decides the test, so a bare
`[[ ]]` anywhere before it asserts nothing. Heredoc bodies are skipped: they
run in their own shell and are judged by the test's status checks instead.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
TEST_START = re.compile(r"^@test\s.*\{\s*$")
HEREDOC = re.compile(r"(?<!<)<<(?!<)-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1")


def is_bare_assertion(statement: str) -> bool:
    return statement.startswith("[[") and statement.endswith("]]")


def inspect_file(path: Path) -> list[int]:
    findings: list[int] = []
    in_test = False
    terminator = ""
    statements: list[tuple[int, str]] = []

    for number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not in_test:
            if TEST_START.match(raw):
                in_test = True
                statements = []
            continue
        if terminator:
            if raw.strip() == terminator:
                terminator = ""
            continue
        if raw == "}":
            findings.extend(line for line, text in statements[:-1] if is_bare_assertion(text))
            in_test = False
            continue
        stripped = raw.strip()
        if not stripped or stripped.startswith("#"):
            continue
        statements.append((number, stripped))
        heredoc = HEREDOC.search(stripped)
        if heredoc:
            terminator = heredoc.group(2)
    return findings


def main(argv: list[str]) -> int:
    sources = [Path(arg).resolve() for arg in argv] if argv else sorted((PROJECT_ROOT / "tests").glob("*.bats"))
    findings = [(source, line) for source in sources for line in inspect_file(source)]
    if findings:
        for source, line in findings:
            print(f"{source}:{line}: bare [[ ]] before the last statement never fails on bash 3.2; append '|| return 1'")
        return 1
    print(f"bats-assertion-audit-ok files={len(sources)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
