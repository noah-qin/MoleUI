---
name: bugs
description: "Mole incident catalog for cleanup safety, bounded probes, cancellation, dry-run parity, and actionable gates. Use for a Mole safety-sensitive diff; not for docs, release notes, or generic review."
---

# Mole bug patterns

Generic review belongs to Waza `check`; root-cause investigation of a live failure belongs to `hunt`.

## Route before loading details

Choose only the reference families touched by the evidence. A whole-project audit should classify surfaces first instead of loading every incident narrative.

| # | Recurring shape | First probe | Read |
|---|---|---|---|
| 1 | Deletion candidate built from a weak name signal | Inspect name, bundle-id, fallback globs, and failed-owner shortcuts | [Deletion evidence and final sink](references/deletion-evidence-and-final-sink.md) |
| 2 | Existence or idleness decided by one probe | Enumerate every legitimate location and unknown outcome | [Deletion evidence and final sink](references/deletion-evidence-and-final-sink.md) |
| 3 | Guard present on only one branch | Diff dry-run, real, direct, fallback, and final-sink paths | [Deletion evidence and final sink](references/deletion-evidence-and-final-sink.md) |
| 4 | Unbounded external command | Count producer, consumer, inner-loop, and action bounds | [Bounds, Shell, TTY, and parsing](references/shell-and-test-pitfalls.md) |
| 5 | Bash 3.2, errexit, or pipefail trap | Check empty arrays, `fn || handler`, and optional actions | [Bounds, Shell, TTY, and parsing](references/shell-and-test-pitfalls.md) |
| 6 | TTY, stdin, or process-group theft | Inspect background workers and commands that may prompt | [Bounds, Shell, TTY, and parsing](references/shell-and-test-pitfalls.md) |
| 7 | System output parsed as a stable API | Force locale, validate shape, and join on identifiers not headings | [Bounds, Shell, TTY, and parsing](references/shell-and-test-pitfalls.md) |
| 8 | Persisted derived data outlives its algorithm | Trace schema, TTL, evidence fingerprint, and mutations | [State, accounting, and progress](references/state-accounting-and-progress.md) |
| 9 | Two paths compute one number differently | Find every producer and choose one definition | [State, accounting, and progress](references/state-accounting-and-progress.md) |
| 10 | Slow work looks frozen | Find operations over roughly one second outside feedback | [State, accounting, and progress](references/state-accounting-and-progress.md) |
| 11 | Regression test cannot fail | Prove positive control and pre-fix red state | [Test validity and refusal diagnostics](references/test-validity-and-refusal-diagnostics.md) |
| 12 | Gate cannot explain why it refused | Map each reason to one cause and a next action that fails on the broken state | [Test validity and refusal diagnostics](references/test-validity-and-refusal-diagnostics.md) |
| 13 | Mutation target is also accepted as a discovery container | Compare the recursive scan-root namespace with every purge target basename | [Deletion evidence and final sink](references/deletion-evidence-and-final-sink.md) |
| 14 | Owner metadata is treated as a complete, atomic inventory | Identify who writes it, whether absence is authoritative, and what locks mutation | [Deletion evidence and final sink](references/deletion-evidence-and-final-sink.md) |
| 15 | Cancellation stops one helper but later work continues | Classify each 124 as skip, section budget, or sticky cancel before tracing callers | [Bounds, Shell, TTY, and parsing](references/shell-and-test-pitfalls.md) |
| 16 | Async or cached data has no generation or freshness contract | Bind results to a request epoch and keep each sample's time, stale, and completeness fields together | [State, accounting, and progress](references/state-accounting-and-progress.md) |
| 17 | Publication gate trusts ambiguous or pre-existing state | Require exact source/tag equality, one generated target, and an expected-absence ref lease | [Test validity and refusal diagnostics](references/test-validity-and-refusal-diagnostics.md) |
| 18 | A sandbox well-known path is treated as app-private leftovers | Resolve Data/Downloads, Desktop, Pictures, Music, and Movies physically against $HOME | [Deletion evidence and final sink](references/deletion-evidence-and-final-sink.md) |

AGENTS.md keeps each rule stated fully enough to obey plus its test anchor; the incident story lives in these references or in `release-flow`, and the AGENTS.md bullet points to the section that holds it. Moving a story here is a merge, never the deletion of a rule that still constrains behavior.

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
- Are timeouts classified by probe, sizing, removal, or section scope, with unknown evidence refusing deletion and cancellation stopping later mutation?
- Are probe and sink bound to the same physical parent and target?
- Do dry-run and real mode start from the same eligible plan without reusing stale authorization?
- Are cheap missing, protected, whitelisted, and compiled-model filters ahead of recursive probes?
- Does one cumulative deadline cover the dynamic scan scope, with checkpoints in nested loops?
- Do refused, filtered, timed-out, or failed items stay out of cleaned counts and reclaimed bytes?
- Can large candidates avoid per-item size work without making the reported total false?

Do not trade final-sink rebinding or fail-closed owner checks for speed. Optimize absent targets, duplicated discovery probes, report-only work, and wrong-scope scans first.

## Working contract

- Before proposing a remedy, apply the Product Decision Filter in `AGENTS.md`: a new flag, environment variable, or visible retry message is a product change, even when the underlying fix is a safety improvement. Use the existing state/accounting reference when deciding what belongs in the normal summary.
- A sandbox well-known directory is user data until physical resolution proves otherwise. `Data/Downloads` is usually `~/Downloads` under another name.
- A refusal next step that succeeds on the broken state is not a next step. Do not relax the gate to make the message nicer.
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
