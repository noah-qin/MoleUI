# Bounds, Shell, TTY, and parsing

Read this reference when changing Shell code, Bats tests, update/install flows, timeout wrappers, TTY handling, plist fixtures, or macOS-version-specific CI behavior. The defect classes and repo-wide probes stay in the parent `bugs` skill.

## 4. An external command or its consumer is unbounded

`du`, `mdfind`, `find`, `xcrun simctl`, `system_profiler`, `ioreg`, and package tools can stall on a healthy but slow machine. Every production `du -s` route stays behind `run_with_timeout`; `tests/core_timeout.bats` pins the class.

Check more than the obvious command:

- Put checkpoints in every nested loop, not just each outer root (`edb214c0`).
- Tune against the slowest healthy case. CoreSimulatorService needed a warm-up retry after a two-second bound falsely reported it unavailable (`35d856f1`).
- Materialize a bounded producer completely and discard its output on nonzero status. Process substitution plus `|| true` must not feed a partial `find` prefix into deletion.
- Keep probe and action pattern, type, age, and depth identical.
- Time producer and consumer separately before raising a timeout. A 2.3-second `lsregister` dump followed by one command substitution per input line still becomes minutes.
- Bound installed-binary `--version` and `--help` verification. Broken executables are the ones most likely to hang.
- Keep install and update single-flight per target directory so one process cannot verify another generation.

```bash
for command_name in 'du -s' mdfind xcrun system_profiler ioreg brew; do
    printf '%-16s total=%-4s wrapped=%s\n' "$command_name" \
        "$(command grep -rn -- "$command_name" lib/ bin/ | wc -l | tr -d ' ')" \
        "$(command grep -rn -- "$command_name" lib/ bin/ | command grep -c run_with_timeout)"
done
```

## 5. Bash 3.2, errexit, and pipefail change meaning

macOS ships Bash 3.2 and Mole runs with nounset.

- Guard empty array expansion before `"${arr[@]}"`; an empty array under `set -u` can abort a scan and orphan its spinner (`893b4e6f`, `2c06cb91`).
- `fn || handler` disables errexit inside `fn` for the whole function. Safety-critical steps use explicit `if ! command; then return 1; fi` (`a33a0b51`).
- Do not rely on a caller's temporary `set +e` window for graceful degradation. Capture the status where the command runs.
- Optional `[[ -n "$value" ]] && action` returns 1 when absent. Use `if/fi` inside status-sensitive blocks.

```bash
command grep -rn '\$\{[a-z_]*\[@\]\}' lib/ bin/
```

## 6. Background work steals TTY, stdin, or process groups

The Perl timeout fallback can hand the controlling terminal to its child. A background metadata worker then stopped the foreground uninstall prompt with SIGTTIN (`c93afca3`). BSD `mv` and `cp` can also prompt on stderr and read stdin when a destination is unwritable (`63030e3a`).

Every background worker that calls `run_with_timeout` closes stdin with `< /dev/null`. Commands that can prompt also use their noninteractive or force option. Menu and scan traps save and restore the caller's traps; `lib/ui/menu_paginated.sh` is the reference.

## 7. System command output is treated as an API

macOS command output is localized, drifts between releases, and can print errors where data is expected.

- Force `LC_ALL=C` for parsed metric subprocesses (`51b352a2`, `fa05b8cc`, `4e83743b`).
- Validate field shape before trusting it: absolute path, numeric value, expected key, or exact enum.
- Keep `DTSDKBuild` build identifiers separate from `DTPlatformVersion` versions (`f0896d03`).
- Reject PlistBuddy's missing-file prose as data.
- Use stock macOS semantics when checking flags. BSD `grep -Z` means `--decompress`; a developer alias may hide that.
- Prefer exit codes, plist keys, and machine-readable output over prose matching.

Use `command grep` when flag behavior matters, because the interactive environment may alias it.

## 15. Cancellation is local unless orchestration makes it sticky

For a destructive command, timeout `124` and signal-derived statuses `>=128` cancel the remaining command, not merely the current helper. Carry that decision through every boundary:

- A best-effort loop must check a pending cancellation before probing or registering the next candidate.
- A helper that reports ordinary misses as success must return a pending cancellation before starting the next family.
- Command substitution, subshells, and background workers do not mutate the parent's shell variables. Return the status, or use an explicit parent-readable channel, then record it again in the parent.
- A parallel coordinator stops and reaps peer workers, preserves cancellation over ordinary failures, and prevents the next rendered section from starting.
- Dry-run uses the same cancellation contract as real cleanup. A preview ledger is still downstream work and must not continue after safety evidence becomes unavailable.

The regression shape matters. Make the first candidate return 124 or 130 and make the second candidate succeed if reached. Assert the exact top-level status plus the absence of a positive trace from the second probe, preview registration, sink, and later section. If both candidates independently time out, the test cannot prove cancellation was sticky.

Do not hide a cancelled safety probe behind `|| true`, a warning plus `return 0`, or a worker-local exported variable. Those shapes turn a global stop into a local skip.

## Focused pitfalls

- **`BASH_SOURCE` / `$0` change meaning when a function moves files**: they name the file the code lives in, so copy-paste extraction is not behavior-preserving. `mole` captures `MOLE_ENTRY_SCRIPT="${BASH_SOURCE[0]}"` before sourcing anything, and update code reads that stable entrypoint. Before extracting a function, grep it for `BASH_SOURCE`, `$0`, and `FUNCNAME`. Regression coverage lives in `tests/update.bats`.
- **Every `du -s` must run under `run_with_timeout`**: one stalled mount can wedge the whole scan. Use `MOLE_TIMEOUT_DISK_VERIFY_SEC`. `tests/core_timeout.bats` pins the source invariant across `lib/` and `bin/`.
- **Bash 3.2 nounset rejects empty array expansion**: guard `"${arr[@]}"` with `[[ ${#arr[@]} -gt 0 ]]` under `set -u`.
- **`fn || handler` disables errexit inside `fn` for its whole body**: safety-critical steps must use explicit `if ! cmd; then return 1; fi` checks and installers must verify the installed binary's reported version before claiming success. `tests/install_checksum.bats` covers the exact caller shape.
- **`[[ -n "$var" ]] && cmd` returns 1 when the variable is empty**: inside exit-code-sensitive blocks, use `if/fi` so an optional action does not turn the block into failure.
- **Bats heredocs share stdin with `read -n1`**: an inner `read -r -s -n1` can consume the next byte of the heredoc source. Redirect the function under test from `/dev/null`.
- **macOS `script(1)` rejects socket-backed stdin**: PTY test helpers must redirect the wrapper's stdin from `/dev/null` or `script` can fail before starting the child. Capability probes use `/usr/bin/true`, not the absent `/bin/true`; inspect the actual failure before classifying it as unavailable TTY support, or live terminal tests silently skip.
- **`run_with_timeout` execs the binary and bypasses shell-function mocks**: tests must use a PATH stub directory for commands such as `osascript`.
- **CI runners may lack `/Library/PrivilegedHelperTools`**: orphan-service tests should exercise `/Library/LaunchDaemons`, which exists on GitHub macOS runners.
- **A test can pass vacuously after an early return**: `MOLE_TEST_MODE=1` can leave `$output` empty, and a final negative assertion then passes. End assertions with `|| return 1`, override test mode when the body must run, and add a positive control proving the output path executed. In an inner heredoc script use `|| exit 1`. Confirm the bracket behavior with a minimal repro when it matters: a non-final `[[ ]]` can be swallowed while `[ ]` still gates.
- **A large payload piped into `grep -q` leaks a broken-pipe line into user output**: `grep -q` exits on its first match, and the `printf` still writing into that closed pipe takes SIGPIPE, which bash reports as `printf: write error: Broken pipe` on stderr. The live-cache owner probe fed the whole process table that way and the message landed mid-run in `mo clean`. Pass the data by here-string instead. Small variables holding a few lines of command output finish in one write and are unaffected, so the existing `echo "$var" | grep -q` sites are fine.
- **Normalize with `10#` before any numeric comparison**: `[[ a -le b ]]` evaluates arithmetically, so a leading zero is read as octal and `0123` ranks below `100`, while `08` and `09` are not valid octal at all and abort the test with a bash error on stderr. A `^[0-9]+$` guard does not prevent either. Codex build numbers compared this way could have called a newer staged build superseded.
- **`SECONDS` advances in whole seconds, so a 1s budget is not a second**: a deadline built as `SECONDS + 1` really means "until the next second boundary" and can collapse to almost nothing, making `_mole_timeout_with_deadline` return 124 before the command ever runs. Every timeout constant is 2 or more for this reason. A test of clamp arithmetic invokes the helper directly after resetting `SECONDS`; an exact value asserted across command substitution still races the fork on a loaded runner even with a larger window. When the fork is the behavior under test, assert a safe range or property instead of one remaining-second literal.
- **BSD grep has no GNU null-output `-Z` contract**: on stock macOS it means `--decompress`. Enumerate files with `find ... -print0`, then probe each file with `grep -qF`.
- **PlistBuddy reports missing-file creation on stdout**: redirect both stdout and stderr when creating plist fixtures so diagnostic prose does not pollute Bats `$output`.
- **macOS 14 Bash can fire errexit through an if-guarded exported mock**: a failing exported `sudo` function inside an `if fn; then` path may terminate a `set -e` script on that runner while passing locally. Around the first sudo probe, disable errexit only for the probe and restore it before validation-gate returns. CI-only failures must print exit status, output, and a mock call trace rather than a bare return-code assertion.
- **Expected capability absence is not probe failure**: keep `ready`, `not applicable`, and `misconfigured or unknown` distinct. A Mac with standalone Command Line Tools and no Xcode app has no simulator surface, so missing `simctl` is a quiet skip; an explicit invalid `DEVELOPER_DIR` remains actionable. Tests prove the not-applicable path does not invoke the unavailable owner command or emit warning activity.
- **Fixed-width prefixes may have a free-form remainder**: after validating numeric and enum columns, join the remaining fields instead of assigning semantic meaning to one whitespace token. Darwin process `comm` values can contain spaces; trimming them to the first word destroyed zombie-parent attribution for helper apps. Keep primary and fallback formats separate when their fields carry different semantics.
