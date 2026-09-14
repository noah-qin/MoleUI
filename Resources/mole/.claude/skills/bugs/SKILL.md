---
name: bugs
description: "Mole incident catalog for destructive cleanup safety, bounded Shell/macOS probes, cancellation and concurrency, dry-run/real parity, async freshness, cache and accounting consistency, Bats validity, and actionable gates. Use for a Mole bug or safety-sensitive diff involving deletion evidence, owner metadata, unknown process state, timeouts or signals, parallel workers, stale results, system parsing, persisted derivations, totals, progress, publication gates, or tests. Not for docs, release planning or notes, generic review, or other repositories."
---

# Mole bug patterns

Generic review belongs to Waza `check`; root-cause investigation of a live failure belongs to `hunt`.

## Route before loading details

Choose only the reference families touched by the evidence. A whole-project audit should classify surfaces first instead of loading every incident narrative.

| # | Recurring shape | First probe | Read |
|---|---|---|---|
| 1 | Deletion candidate built from a weak name signal | Inspect name, bundle-id, and fallback globs | [Deletion evidence and final sink](references/deletion-evidence-and-final-sink.md) |
| 2 | Existence or idleness decided by one probe | Enumerate every legitimate location and unknown outcome | [Deletion evidence and final sink](references/deletion-evidence-and-final-sink.md) |
| 3 | Guard present on only one branch | Diff dry-run, real, direct, fallback, and final-sink paths | [Deletion evidence and final sink](references/deletion-evidence-and-final-sink.md) |
| 4 | Unbounded external command | Count producer, consumer, inner-loop, and action bounds | [Bounds, Shell, TTY, and parsing](references/shell-and-test-pitfalls.md) |
| 5 | Bash 3.2, errexit, or pipefail trap | Check empty arrays, `fn || handler`, and optional actions | [Bounds, Shell, TTY, and parsing](references/shell-and-test-pitfalls.md) |
| 6 | TTY, stdin, or process-group theft | Inspect background workers and commands that may prompt | [Bounds, Shell, TTY, and parsing](references/shell-and-test-pitfalls.md) |
| 7 | System output parsed as a stable API | Force locale and validate shape before accepting data | [Bounds, Shell, TTY, and parsing](references/shell-and-test-pitfalls.md) |
| 8 | Persisted derived data outlives its algorithm | Trace schema, TTL, evidence fingerprint, and mutations | [State, accounting, and progress](references/state-accounting-and-progress.md) |
| 9 | Two paths compute one number differently | Find every producer and choose one definition | [State, accounting, and progress](references/state-accounting-and-progress.md) |
| 10 | Slow work looks frozen | Find operations over roughly one second outside feedback | [State, accounting, and progress](references/state-accounting-and-progress.md) |
| 11 | Regression test cannot fail | Prove positive control and pre-fix red state | [Test validity and refusal diagnostics](references/test-validity-and-refusal-diagnostics.md) |
| 12 | Gate cannot explain why it refused | Map each reason code to one cause and next action | [Test validity and refusal diagnostics](references/test-validity-and-refusal-diagnostics.md) |
| 13 | Mutation target is also accepted as a discovery container | Compare the recursive scan-root namespace with every purge target basename | [Deletion evidence and final sink](references/deletion-evidence-and-final-sink.md) |
| 14 | Owner metadata is treated as a complete, atomic inventory | Identify who writes it, whether absence is authoritative, and what locks mutation | [Deletion evidence and final sink](references/deletion-evidence-and-final-sink.md) |
| 15 | Cancellation stops one helper but later work continues | Trace 124 and signal statuses across loops, subshells, workers, and section orchestration | [Bounds, Shell, TTY, and parsing](references/shell-and-test-pitfalls.md) |
| 16 | Async or cached data has no generation or freshness contract | Bind results to a request epoch and keep each sample's time, stale, and completeness fields together | [State, accounting, and progress](references/state-accounting-and-progress.md) |
| 17 | Publication gate trusts ambiguous or pre-existing state | Require exact source/tag equality, one generated target, and an expected-absence ref lease | [Test validity and refusal diagnostics](references/test-validity-and-refusal-diagnostics.md) |

## Trace the complete mutation lifecycle

For cleanup, purge, optimize, analyze deletion, or uninstall work, review the complete chain rather than the reported branch:

```text
discover or plan
  -> cheap irreversible filters
  -> owner and open-handle probes
  -> size or metadata work
  -> final owner re-probe
  -> parent and target identity rebind
  -> deletion or Trash sink
  -> accounting, cancellation, and user output
```

At every transition, answer:

- Does live or unknown state fail closed?
- Do timeout and signal statuses remain observable and stop later mutation?
- Are probe and sink bound to the same physical parent and target?
- Do dry-run and real mode start from the same eligible plan without reusing stale authorization?
- Are cheap missing, protected, whitelisted, and compiled-model filters ahead of recursive probes?
- Does one cumulative deadline cover the dynamic scan scope, with checkpoints in nested loops?
- Do refused, filtered, timed-out, or failed items stay out of cleaned counts and reclaimed bytes?
- Can large candidates avoid per-item size work without making the reported total false?

Do not trade final-sink rebinding or fail-closed owner checks for speed. Optimize absent targets, duplicated discovery probes, report-only work, and wrong-scope scans first.

## Working contract

- Sweep siblings by call-site shape, not filename or helper name. Report `checked N / defective M / not applicable K`.
- A recurring fix ships with a regression or source invariant that fails against the pre-fix code.
- Treat tests as production consumers only after proving the production helper ran. Negative assertions require a positive trace.
- A cancellation regression makes the next candidate otherwise eligible, then proves its probe and sink never run. Making every candidate fail for the same reason is a false sticky-cancellation test.
- Absence-sensitive tests use an isolated `HOME` or fixture root; a shared `setup_file` home is not isolation.
- Reproduce CI through `MOLE_TEST_NO_AUTH=1 ./scripts/test.sh` when possible. If invoking Bats directly with jobs, preserve `--no-parallelize-within-files`; files share state and raw `bats --jobs 6 file.bats` changes semantics.
- Treat specialist or AI reports as leads. Read the implementation, callers, fallback branches, and final sink yourself.

## Verification bar

Use the hotspot commands in `AGENTS.md`; do not guess a narrower verifier. A typical Shell safety change finishes with:

```bash
./scripts/check.sh --format
MOLE_TEST_NO_AUTH=1 bats tests/<area>.bats
MOLE_TEST_NO_AUTH=1 ./scripts/test.sh
go test ./...
MOLE_TEST_NO_AUTH=1 MOLE_DRY_RUN=1 ./mole clean --dry-run
```

Never infer a production defect from a function name, comment, string, fixture, or `_test.go` match. Confirm the live call path and verify red-green before reporting the class fixed.
