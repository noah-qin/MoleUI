#!/usr/bin/env python3
"""Find shell functions that are the same code wearing different names.

Grepping for a name does not find this class. The copies that matter are the
ones where someone renamed the variables: `_dev_safe_clean_process_guarded` and
`_user_safe_clean_process_guarded` differed only by a `_MOLE_DEV_` vs
`_MOLE_USER_` prefix, and nine delete guards each re-implemented the same
six-line process-state translation. Reviewing by name reads all of them as
distinct helpers.

So compare structure instead: strip comments, then rewrite local identifiers and
string literals to placeholders, and hash what is left. Functions that collapse
to the same hash are the same function.

The duplication itself is rarely the bug. The bug is that one copy drifts and
the other copies still read correctly in review, which is how a guard folding
"could not tell" into "not running" survives a careful reading of its eight
siblings. That is why this is a gate and not a report.

Usage:
    scripts/audit_function_duplication.py            # gate, exits non-zero on a new group
    scripts/audit_function_duplication.py --list     # show every group, exit 0
"""

from __future__ import annotations

import hashlib
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

# Directories worth comparing. Tests legitimately repeat setup shapes.
SEARCH_GLOBS = ("lib/**/*.sh", "bin/*.sh")

# Below this a match is noise: three-line wrappers around one call collide by
# accident and say nothing about drift risk.
MIN_BODY_LINES = 5

# Groups that are the same shape on purpose. Keyed by the member names, sorted.
# A new group is a review question, not automatically a defect: add it here with
# the reason it stays, or collapse it. An entry whose members no longer exist is
# reported too, so this list cannot quietly outlive what it documents.
ALLOWED_GROUPS: dict[tuple[str, ...], str] = {
    ("log_info", "log_success", "log_warning"): (
        "one frame per severity; they differ by colour and icon, which is the whole point"
    ),
    ("_ms_get_terminal_height", "_pm_get_terminal_height"): (
        "menu_simple and menu_paginated are deliberately independent modules; "
        "sharing a helper would couple the fallback UI to the paginated one"
    ),
    ("show_history_help", "show_installer_help"): (
        "same help frame, different command text; the frame is the shared part and already is"
    ),
}

FUNC_START = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)\(\)\s*\{\s*$")
FUNC_END = re.compile(r"^\}\s*$")


def normalize(body: list[str]) -> str:
    """Reduce a body to its structure: control flow, operators, call arity."""
    kept = []
    for line in body:
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        kept.append(stripped)
    text = "\n".join(kept)
    text = re.sub(r"_MOLE_[A-Z0-9_]+", "VAR", text)
    text = re.sub(r"\b_[a-z][a-z0-9_]*\b", "FN", text)
    text = re.sub(r'"[^"]*"', "S", text)
    text = re.sub(r"'[^']*'", "S", text)
    return text


def collect_functions() -> dict[tuple[str, str], list[str]]:
    functions: dict[tuple[str, str], list[str]] = {}
    paths: list[Path] = []
    for pattern in SEARCH_GLOBS:
        paths.extend(sorted(REPO_ROOT.glob(pattern)))
    for path in paths:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
        index = 0
        while index < len(lines):
            match = FUNC_START.match(lines[index])
            if not match:
                index += 1
                continue
            name = match.group(1)
            cursor = index + 1
            body: list[str] = []
            while cursor < len(lines) and not FUNC_END.match(lines[cursor]):
                body.append(lines[cursor])
                cursor += 1
            if len(body) >= MIN_BODY_LINES:
                rel = path.relative_to(REPO_ROOT).as_posix()
                functions[(rel, name)] = body
            index = cursor + 1
    return functions


def find_groups() -> list[tuple[tuple[str, ...], list[tuple[str, str]]]]:
    buckets: dict[str, list[tuple[str, str]]] = {}
    for (rel, name), body in collect_functions().items():
        digest = hashlib.sha256(normalize(body).encode("utf-8")).hexdigest()
        buckets.setdefault(digest, []).append((rel, name))
    groups = []
    for members in buckets.values():
        if len(members) < 2:
            continue
        key = tuple(sorted(name for _, name in members))
        groups.append((key, sorted(members)))
    groups.sort(key=lambda item: (-len(item[1]), item[0]))
    return groups


def main() -> int:
    groups = find_groups()
    listing = "--list" in sys.argv[1:]

    if listing:
        for key, members in groups:
            status = "allowed" if key in ALLOWED_GROUPS else "NEW"
            print(f"[{len(members)}] {status}")
            for rel, name in members:
                print(f"    {name}  ({rel})")
        print(f"\n{len(groups)} group(s); {len(ALLOWED_GROUPS)} allowed")
        return 0

    seen = {key for key, _ in groups}
    unexpected = [(key, members) for key, members in groups if key not in ALLOWED_GROUPS]
    vanished = [key for key in ALLOWED_GROUPS if key not in seen]

    if unexpected:
        print("error: shell functions share a body under different names", file=sys.stderr)
        for key, members in unexpected:
            print("", file=sys.stderr)
            for rel, name in members:
                print(f"    {name}  ({rel})", file=sys.stderr)
        print(
            "\nCollapse them, or add the group to ALLOWED_GROUPS in this script with the\n"
            "reason it stays. Duplication here is cheap to write and expensive to keep:\n"
            "the copy that drifts still reads correctly next to the ones that did not.",
            file=sys.stderr,
        )
        return 1

    if vanished:
        print("error: ALLOWED_GROUPS lists groups that no longer exist", file=sys.stderr)
        for key in vanished:
            print(f"    {', '.join(key)}", file=sys.stderr)
        print("\nDrop the stale entries so this list keeps describing the code.", file=sys.stderr)
        return 1

    print(f"function-duplication-ok groups={len(groups)}/{len(ALLOWED_GROUPS)} allowed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
