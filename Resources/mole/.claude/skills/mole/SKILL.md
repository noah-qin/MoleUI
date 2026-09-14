---
name: mole
description: "Drive the installed Mole CLI (`mo`) safely, including machine-readable status, analysis, history, and dry-run surfaces. Use before running `mo` on a user's Mac. Not for editing or reviewing Mole source code."
---

# Using Mole from an agent

Mole (`mo`) cleans, uninstalls, analyzes, optimizes, and monitors a Mac. It is
a real deletion tool operating on someone's live machine, so the way an agent
uses it differs from the way a human does: never guess, never let a TUI decide,
and never let a destructive command run without the user having seen the list.

## The rules

1. **Preview before you delete. Always.** Every destructive command takes
   `--dry-run`. Run it, read the result, show the user what would go, and only
   then offer the real run. An agent that runs `mo clean` before `mo clean
   --dry-run` has skipped the only step the user can veto.
2. **The user runs the destructive command, not you**, unless they explicitly
   asked you to do it in the current turn. "Clean my Mac" is such an ask;
   "why is my disk full" is not.
3. **Never parse a TUI frame.** Interactive `mo analyze` and terminal-attached
   `mo status` are full-screen Go programs whose output is drawn, not printed.
   Use `mo analyze --json`, `mo status --json`, or `mo status --watch` instead.
4. **Never invent flags.** The command surface is small and listed here; if
   something is not on this page, run `mo <command> --help` and read it, do not
   assume a `--yes` or `--force` exists.
5. **Protection is a whitelist, not an argument.** If the user wants a cache
   kept, the answer is `mo clean --whitelist`, not a hand-rolled `find`. Never
   work around Mole's safety layer with raw `rm`.

## What answers which question

| The user asks | Command |
|---|---|
| "What is eating my disk?" | `mo analyze --json` (whole disk) or `mo analyze --json <path>` |
| "Free up space" | `mo clean --dry-run`, review, then `mo clean` |
| "Remove this app completely" | `mo uninstall --list` to get the name, `mo uninstall <app> --dry-run`, then `mo uninstall <app>` (no app argument opens the interactive selector) |
| "My Mac feels slow" / caches look broken | `mo optimize --dry-run` then `mo optimize` |
| "Clean up my old projects" | `mo purge --dry-run` then `mo purge` |
| "Get rid of downloaded installers" | `mo installer --dry-run` then `mo installer` |
| "What did Mole delete?" | `mo history --json --limit 20` |
| One CPU / memory / disk / network snapshot | `mo status --json` |
| A short time series for diagnosis | `mo status --watch --interval 1s` (NDJSON; stop after enough samples) |

## Machine-readable surfaces

These five surfaces are the agent-facing API. Everything else is for humans.

**Disk usage.** `mo analyze --json` prints one JSON object: `path`, `overview`,
`total_size`, `total_files`, `large_files[]`, and `entries[]` of `{name, path,
size, is_dir, insight, cleanable, last_access}`. `size` is bytes.
`insight: true` marks an entry Mole considers noteworthy (a large iOS backup, a
runaway cache) and is set only in overview mode. Pass a path to scope it:
`mo analyze --json ~/Library`; the flag must come before the path because the
Go flag parser stops at the first positional argument.

**Cleanup history.** `mo history --json [--limit N]` (N is 1-200) prints
`logs` (paths of the operations and deletions logs), `limit`, `sessions[]` with
`command`, `started_at`, `ended_at`, `items`, `size`, `operation_count`,
`failed_tasks`, and an `actions` breakdown of removed / trashed / skipped /
failed / rebuilt / other, plus a structured `deletions[]` array of the logged
paths. This is how you answer "did Mole delete my file" without guessing.

**Installed apps.** `mo uninstall --list` piped (stdout not a TTY) prints the
app inventory as JSON: name, bundle id, uninstall name, path, size. This is how
you find the exact `<UNINSTALL NAME>` argument without touching the selector TUI.

**The dry-run path list.** `mo clean --dry-run` prints a summary to the
terminal and writes every candidate path to `~/.config/mole/clean-list.txt`.
Read that file, not the terminal output, when you need to reason about or show
the user exactly what a real run would remove. This list is clean-only: `mo
purge --dry-run` and `mo installer --dry-run` print their candidates to the
terminal and write no file.

**System status.** `mo status --json` prints one metrics snapshot. It also
switches to JSON automatically when stdout is not a TTY, but pass `--json`
explicitly in scripts so intent stays obvious. `mo status --watch --interval
1s` emits one complete JSON object per line from a warm collector. Bound the
watch duration or sample count and terminate it after collecting the evidence
the user asked for; do not leave an unbounded monitor running in the background.

## Command notes worth knowing

- `mo clean` also sweeps leftovers from apps the user already deleted. It does
  not touch installed apps; that is `mo uninstall`.
- `mo clean --external <path>` cleans macOS metadata off an external volume.
- `mo purge` removes rebuildable project artifacts: local build output
  (`target/`, `build/`, `dist/`, `.next/`) and dependency directories that need
  a network to restore (`node_modules/`, `Pods/`, `venv/`, `vendor/`). A purge
  is therefore not always recoverable offline, so say which kind the candidates
  are before running it. `mo purge --paths` configures which directories are
  scanned; `--include-empty` shows zero-size candidates.
- `mo optimize` refreshes caches and system services. It is the one destructive
  command whose effects are not "files disappear", so say what it will do
  before running it.
- `mo update` self-updates; `mo update --nightly` installs unreleased `main`.
  Do not run either on a user's behalf without being asked.
- `--debug` on any command prints the detailed operation log. Reach for it when
  a command silently did nothing; do not leave it on in normal use.

## When something goes wrong

**`mo clean` deletions are permanent by default.** Cache cleanup removes files
rather than moving them to the Trash, so there is usually nothing to restore.
That is exactly why rule 1 exists: the dry-run is the undo. `mo uninstall` is
the exception: it routes the app and its leftovers through the Trash, so an
uninstalled app is recoverable until the Trash is emptied.

What you do have is a record. `mo history --json` returns every logged deletion
in its `deletions[]` array; the raw log at the path in `logs` (one tab-separated
line per deletion: timestamp, mode, size, status, path) is the fallback for
entries older than `--limit`. So when a user asks "did Mole take my file", answer
from that record instead of guessing. Then add the path to the whitelist (`mo
clean --whitelist`) so the next run leaves it alone.
