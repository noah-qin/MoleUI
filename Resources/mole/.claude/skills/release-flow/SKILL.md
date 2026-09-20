---
name: release-flow
description: "Mole CLI release runbook for distribution channels, pre-flight checks, capital-V tags, artifacts, and curated-note handoff. Use when assessing or executing a Mole release. Not for release-note copy alone or ordinary code review."
---

# Mole CLI Release Flow

Tag-driven flow. The `release.yml` workflow watches `'V*'` tag pushes (capital `V`), builds amd64 and arm64 binaries on macOS, generates `SHA256SUMS`, attaches build provenance, creates the GitHub Release without notes, then opens a Homebrew core PR.

## Distribution channels

| Channel | What ships | Trigger | Automation |
|---|---|---|---|
| Nightly (`mo update --nightly`) | `main` HEAD via `install.sh` | Any commit pushed to `main` | Automatic; no tag or release involved |
| GitHub stable release | amd64/arm64 binaries + `SHA256SUMS` | Push a capital-`V` tag | `release.yml` builds and creates the release; curated notes are a manual follow-up |
| Homebrew core | Version-bump PR to `Homebrew/homebrew-core` | Same `V*` tag workflow | Automatic PR; merge timing is upstream's |

At the start of any release-flavored task, restate which channels this run will touch and which it will not, and confirm with the maintainer before acting. Channel scope is specified by the maintainer, never inferred.

## Pre-flight checklist

Resolve the latest published stable tag from GitHub before choosing the version or review range. Reconcile handoff claims against the current branch, worktree, and remote SHA; an earlier report of uncommitted work may describe commits that have already landed. Review all changes since that stable tag, not just the final fix batch.

1. `grep '^VERSION=' mole` matches the new version.
2. `SECURITY_AUDIT.md` opening line reflects the new version and date.
3. `git status -s` is empty or only contains intentionally staged release work.
4. `git log origin/main..HEAD --oneline` shows only commits you intend to ship.
5. `./scripts/check.sh --format` and `TERM=xterm-256color MOLE_TEST_NO_AUTH=1 MOLE_TEST_JOBS=2 BATS_FORMATTER=tap ./scripts/test.sh` both exit 0.
6. `go test ./...` and `make build` both pass.

Use the Go version declared in `go.mod` for local release builds, matching `actions/setup-go` in CI, then run `scripts/check_release_minos.sh` on both architectures. A newer local Go can raise the minimum macOS version even with `CGO_ENABLED=0`; during V1.54.0 verification, Go 1.27 produced macOS 13 binaries while the declared Go 1.25 toolchain preserved macOS 12. Rebuild with the declared toolchain instead of relaxing the minimum-OS gate.

Capture the test runner's exit status and structured summary, with skipped tests reported separately. After pushing the candidate commit, wait for its required Check, Validation, and CodeQL workflows to finish successfully before tagging that exact SHA. A cancelled run or a green check on another commit is not release evidence.

## Tag and publish

```bash
git push origin main
git tag V<version>          # capital V; release workflow ignores lowercase v
git push origin V<version>
```

Wait for the workflow to finish. The workflow creates the release with assets but `generate_release_notes: false`, so notes must be added in a follow-up step.

After the workflow finishes, verify the release assets before announcing anything: `gh release view V<version> --json assets --jq '.assets[].name'` must list all four `analyze-`/`status-darwin-{amd64,arm64}` binaries, both `binaries-darwin-*.tar.gz` Homebrew tarballs, AND `SHA256SUMS`. Install verification is fail-closed, so a release without a readable `SHA256SUMS` asset makes every install and `mo update` abort by design; a missing checksums file is a release blocker, not a cosmetic gap.

Download all seven assets. Verify the six payload checksums, attestations for all seven tied to the release tag, exact source commit, and `.github/workflows/release.yml`, and each archive's two expected binary members against the raw binary assets. Check Mach-O architecture and minimum macOS version on the downloaded binaries, then run the native architecture's Analyze and Status smoke probes. Successful local builds do not prove the public package contains those bytes.

Then run a **script self-update smoke** before publishing notes or announcing: install the previous stable release through the script channel, run `mo update`, and confirm `mo --version` prints the candidate version. Script-installed clients execute the new tag's `install.sh`, so this is the only gate that exercises their real upgrade path; the pre-flight suite cannot cover it before the release exists. Homebrew is a separate downstream gate: verify it only after the core formula has updated, and never treat a script-channel smoke as proof that Homebrew is ready. If the script smoke fails, pull the release (see the pulling-and-re-releasing pitfall) before anyone is told to update.

Use a fresh archive of the previous tag so ignored local `bin/*` builds cannot contaminate the old installation. Place the isolated prefix and config under a physical user-owned directory; `/tmp` or `/var` aliases and writable ancestors can correctly fail installer path checks. Isolate HOME, config/cache paths, and PATH, block host `brew` and `sudo`, and set `MOLE_TEST_NO_AUTH=1`. Verify `config/install_channel` retains `CHANNEL=stable`, `config/bin/{analyze,status}-go` match the verified release assets, changed installed shell sources match the tag, and a second update reports the current version. Keep the user's existing installation unchanged.

## Apply curated release notes

The curated-notes flow (bilingual format, `gh release edit` instead of `create`, thanks block, and the six-reaction set) is owned by `.claude/skills/release-notes/SKILL.md`. `.agents/skills/release-notes` is a symlink to that canonical directory for Codex discovery, and its Codex-only invocation policy lives in `agents/openai.yaml`; do not replace the symlink with a copied mirror. Follow that skill; do not duplicate its format details here. Version, codename, and emoji go only in the release title; the body h1 is just `Mole`.

After applying notes and the standard reactions through that skill, read back the published title, full body, and all six reactions. Report GitHub Stable and Homebrew availability separately; a successfully opened core PR still needs upstream tests and merge.

## Release-notes craft

Format rules (impact ordering, command existence checks, icon semantics, no em dash, no inline PR refs) live in `.claude/skills/release-notes/SKILL.md` under "Format rules". Keep that skill as the single source of truth for notes formatting.

## Release-only pitfalls

- **`gh release create` conflicts with the workflow-created release**: the workflow already creates the release on tag push, so post-tag note publishing must use `gh release edit`, never `create`.
- **Tag prefix is case-sensitive**: `release.yml` filters on `'V*'`. A lowercase `v1.38.0` tag will not trigger the workflow.
- **Old clients fetch `install.sh` from the release tag, not from main**: a self-updating Mole downloads `raw.githubusercontent.com/tw93/mole/V<tag>/install.sh`, and tag content is immutable. An installer/updater bug therefore reaches existing stable users only through a new tag; fixing main changes Nightly but does not repair an already published stable updater.
- **Never rewrite history an already published tag can reach**: `release.yml` computes the Homebrew core formula's `sha256` from `archive/refs/tags/<TAG>.tar.gz` when the tag push triggers it, and GitHub writes the tag's commit SHA into that archive's pax global header (`comment=<sha>`). Any rewrite that changes an ancestor's SHA therefore re-points the tag onto a rebuilt commit and silently invalidates that checksum, while every file stays byte for byte identical. V1.54.0 broke exactly this way: four days AFTER it shipped, a `git filter-branch` stripped a stray `Co-authored-by: Cursor` trailer from a single commit dated 2026-05-06, which had 956 descendants, so the release commit was rebuilt (`65c98814` to `7b559efd`, same tree `ddb90a20`) and `brew upgrade mole` failed the source checksum for every user who has to build from source, which since Homebrew dropped Intel bottles is every Intel user (#1591). The trap is that the rewrite looks local and content-preserving, so nothing at the time points at a published artifact; the blast radius is every consumer that pinned a hash derived from a tag tarball. Before any `filter-branch` / `filter-repo` / history-rewriting rebase, list the published tags reachable from the rewritten range and treat each one's downstream checksums as invalidated. Auditing whether to rewrite is not the same question as auditing what an earlier rewrite already broke: ask both. Recovery on a live release is a one-line `sha256` PR to `Homebrew/homebrew-core` with the current tarball's hash, and Homebrew will ask the upstream author to confirm the change was benign before merging it, so answer with the two commits' identical tree and the pax header, not with a promise. Bottles are unaffected because BrewTestBot built them from the original download.
- **Pulling and re-releasing a version**: `gh release delete V<old> --cleanup-tag` removes the release and remote tag. Delete the local tag, close the superseded Homebrew core PR with a one-line supersede comment before pushing the replacement tag (`release.yml` refuses to overwrite an existing `mole-<version>` fork branch and reuses, rather than recreates, an open PR for the same head), then bump `VERSION` and `SECURITY_AUDIT.md`, commit `release: V<new>`, tag, and run the normal publish flow. The Homebrew core PR regenerates on the new tag.

When release work touches Shell code or tests, read `.claude/skills/bugs/references/shell-and-test-pitfalls.md` for Bash 3.2 arrays, heredoc input, mock bypasses, and CI-runner quirks.
