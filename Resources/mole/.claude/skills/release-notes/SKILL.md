---
name: release-notes
description: Publish curated release notes for an existing Mole `V<version>` tag, including bilingual format, `gh release edit`, contributor thanks, and reactions. Use only when explicitly asked to edit or publish Mole release notes. Not for release readiness, tagging, or code review.
disable-model-invocation: true
---

# Mole release notes

This skill drives the curated-notes step that runs **after** `release.yml` has finished. The workflow creates the GitHub Release with assets but with `generate_release_notes: false`, so notes must be added in a follow-up `gh release edit` (never `gh release create`, the release already exists, and `create` will conflict).

## Inputs to gather

Before drafting, confirm:

1. **Version**. Capital `V`, e.g. `V1.38.0`. Lowercase `v` does not trigger the workflow and may indicate a botched tag.
2. **CodeName + emoji**. Ask the user. The title format is `V<version> <CodeName> <emoji>`.
3. **Release commit range**. `git log <previous-tag>..V<version> --oneline` gives the raw material.
4. **User-visible behavior changes**. Scan the full commit message bodies (not just subjects) for narrowed detection, removed features, or controlled regressions. These belong in notes even when they are not bug-fix-shaped, because users will encounter the changed boundary in production.
5. **Issue reporters and PR contributors in this cycle**. Use the merged PRs and fixed issues in the release range. Keep it short, for example `Issue reporters and PR contributors this cycle: @a · @b.` Exclude `tw93` and bots.
6. **Verify release exists**. `gh release view V<version> --repo tw93/Mole --json id,name` should return non-empty. If it doesn't, the workflow hasn't finished, wait, don't `gh release create`.

## Pre-flight (cross-check against AGENTS.md)

These should already be true if the tag was pushed correctly. Confirm before publishing notes:

- `grep '^VERSION=' mole` matches `<version>`.
- `SECURITY_AUDIT.md` opening line reflects the new version and date.
- `./scripts/check.sh --format` clean.
- `TERM=xterm-256color MOLE_TEST_NO_AUTH=1 MOLE_TEST_JOBS=2 BATS_FORMATTER=tap ./scripts/test.sh` exits 0.
- `go test ./...` and `make build` pass.

If any fail, stop. The notes can wait; a bad release tag cannot.

## Format

Strictly follow the current compact release shape. Read the latest stable release as the live format reference before drafting: `gh release view --repo tw93/Mole --json tagName,body`.

Structure:

```
<div align="center">
  <img src="https://cdn.tw93.fun/pic/cole.png" alt="Mole Logo" width="120" height="120" style="border-radius:50%" />
  <h1 style="margin: 12px 0 6px;">Mole</h1>
  <p><em>Deep clean and optimize your Mac.</em></p>
</div>

### Changelog

1. **<English headline>**: <one-sentence English elaboration>.
2. ...

### 更新日志

1. **<中文 headline>**：<一句中文说明>。
2. ...

### Thanks

Issue reporters and PR contributors this cycle: @handle1 · @handle2.

### Mole Mac App

Prefer a GUI? [Mole Mac App](https://mole.fit/) brings cleaning, app management, maintenance, disk analysis, and live system status into one native app, with review before deletion and a customizable menu bar HUD. It is $19 once, with lifetime updates and a 14-day refund. [Download and try it](https://mole.fit/download). The CLI stays free and open source.
```

No `---` separators between sections, and no trailing repository link; the published pages end on the Mole Mac App line.

### Format rules (all are documented bugs that have shipped before)

- **Body h1 is just `Mole`**. Version, codename, and emoji live only in the `--title` argument (`V<version> <CodeName> <emoji>`); repeating them in the body header is redundant and has been explicitly rejected before.
- **No em dash anywhere**. Use commas, periods, colons, semicolons, or parentheses.
- **No sponsor list by default**. The current public release style thanks issue reporters and PR contributors for this cycle only.
- **No emoji except the version emoji in the release title**. Body section headers stay plain, including `### Thanks` (the old `Thanks 💖` header is gone from the published pages).
- **No inline PR refs, no inline `@handle` thanks**. PRs and people belong in the dedicated Thanks block only.
- **English block first, 中文 block second**. Same numbered order in both blocks. Same number of items.
- **Order items by user-perceived impact, not commit chronology**. Headline change first; internal safety hardening, performance, and bug fixes follow.
- **Do not describe overview icons that no longer exist**. Analyze overview rows are text-only because emoji width and baselines vary across terminals. If icons return later, they must not imply that user data such as iOS Backups, Xcode Archives, or Old Downloads is safe to delete.
- **Verify every command mentioned in the notes actually exists in HEAD**. The deleted `mo check` / `mo doctor` commands nearly shipped in notes as a "feature" after they were removed.
- **An incident or troubleshooting note is one sentence of symptom plus one command**. No cause taxonomy, no command per branch; the user needs the one line that gets them unstuck. Match the previous release's language treatment for that note: if the last release carried it in one language, do not add a second.
- **Keep the Mole Mac App cross-link to one restrained, fact-backed paragraph**. Validate the product scope, price, updates, refund window, and download URL against the current homepage before publishing.

## Publish

Once the user approves the draft:

```bash
gh release edit V<version> --repo tw93/Mole \
  --title "V<version> <CodeName> <emoji>" \
  --notes-file <path-to-draft>
```

**Never** `gh release create`, it conflicts with the release the workflow already made.

Then add the six reactions with this skill's helper (path is relative to this SKILL.md, not the repo-root `scripts/`): `bash "$(dirname <this SKILL.md>)/scripts/post-reactions.sh" V<version>`.

## After publish

- `gh release view V<version> --repo tw93/Mole --web` (open in browser) so the user can eyeball it.
- Remind the user: the Homebrew Core PR is workflow-driven and should already be in flight; do not re-run it manually unless the workflow log shows a failure.

## When NOT to act

This skill is user-invocable only. It must not run unprompted:

- If the user mentions release notes in passing, draft only; do not call `gh release edit`.
- If `gh release view` shows the release does not exist yet, wait for the workflow; do not create a competing release manually.
- If the user has not given an explicit "publish" / "提交" signal, stop after the draft.

## Helper script

`scripts/post-reactions.sh <tag>` lives next to this SKILL.md and adds the six reactions (`+1`, `laugh`, `hooray`, `heart`, `rocket`, `eyes`) to the release.
