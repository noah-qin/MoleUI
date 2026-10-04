# Mole CLI queue review and execution plan

Snapshot date: 2026-10-03, Asia/Taipei.
Authorization updated: the maintainer approved release of V1.57.0 Steady after reviewing the bilingual draft. This includes the release commit, capital-V tag, GitHub Stable publication, and the existing workflow-driven Homebrew Core update. The maintainer still sends the Issue 1669 follow-up personally; this release does not authorize sending the saved email draft or closing that unresolved report.

## V1.57.0 release preparation

The approved draft describes eight user-visible outcomes from V1.56.1 through the reviewed source at `0292ef090fa8b0bdaec3fe5d4a747b9d4c268cb3`. The complete local runner, declared Go 1.26.0 builds, macOS 12 minimum-version checks, exact Nightly source archive, six review angles, and Check/Validation/CodeQL all passed for that source. The release preparation changes only the source version, this security-document date/version, and this record; it introduces no new command, setting, cleanup target, or animation change beyond the already approved loading mark.

The maintainer approved the V1.57.0 Steady title and draft, with no added title emoji. Tagging still follows successful checks on the release commit. After the workflow creates assets, verify all payload checksums, all seven attestations, archive contents, native Analyze/Status probes, and the isolated V1.56.1-to-V1.57.0 script upgrade before publishing the approved notes. Record GitHub Stable and Homebrew availability separately; opening a Core PR is not a Homebrew release.

Known reporter/runtime boundaries remain explicit: Issue 1669 has fixture proof and delivered Nightly source but no result from the reporter's actual Time Machine namespace; tty7 remains unresolved with the confirmed built-in Terminal workaround; the real large-tree filtering effect is unverified; Issue 1631 awaits capacity samples. None is claimed fully resolved by this release. Earlier no-stable-authorization statements below describe their historical checkpoints and are superseded by the release authorization above.

The release preflight caught one host-dependent idle-cache test. Its shell-function `lsof` mock was bypassed by the production timeout executor; a controlled external unknown result reproduced the failure. The test now uses the shared PATH stub and an isolated process table. A sweep of 61 `lsof` function mocks found a second affected final-owner recheck case, fixed with the same PATH stub; the remaining 59 either route through their local timeout mock or stop before the handle probe. Both old tests failed with a positive external-call trace, and both corrected tests passed without reaching that external command. This is a test-isolation correction with zero production behavior change. The first full preflight failed and the interrupted intermediate retry is not counted as a pass; only the subsequent complete frozen run can authorize the release commit.

## Issue 1669 Time Machine follow-up

The latest `mole_debug_session (1).log` identifies the actual failed path: `/Volumes/com.apple.TimeMachine.localsnapshots` returns `Operation not permitted` during volume discovery. It is an incomplete scan, not a confirmed sibling or timeout. This supersedes the earlier missing-stderr evidence below.

The local fix excludes that exact internal snapshot namespace only after bounded metadata proves root ownership and the same device as the real volume root. Separately mounted namesakes and ordinary unreadable volumes stay in scope; unknown metadata does not authorize exclusion. The original depth-two candidate set, shared deadline, signal propagation, preview plan, and final installation-set check remain intact. No new command, flag, setting, cleanup target, or matcher expansion is introduced.

The production batch regression fails on the unchanged baseline with `PREVIEW_ID=unknown GUARD=guard_login` and the snapshot permission error. Local candidate regressions cover normal leftover plans, live external copies, namesakes, ownership/metadata uncertainty, ordinary unreadable volumes, depth, interruption, and a new sibling appearing after preview. All 12 focused regressions, project formatting/checks, and the complete test runner passed with exit 0, including Go build/vet/tests, module loading, integration, and isolated installation. Both changed source/test files stayed byte-identical throughout the final full run. An initial full-run lint failure was corrected by keeping the Bats helpers before test blocks; no lint rule was suppressed. Security review and all four adversarial angles returned no new blocking findings. Delivery verification is still pending. The reporter's actual snapshot namespace is absent on the maintainer's Mac, so fixture validation is not a reporter-device confirmation.

The maintainer will send the reply personally. Do not send the existing unsent email draft or notify the reporter before the delivery channel contains this fix. The maintainer has now authorized commit and push of the pending fixes after approving the spinner on Kaku. The original authorization line above remains historical, not a standing ship permission. No stable version bump, tag, or release is authorized by the current request to assess release readiness. Issue 1669 remains open pending verified delivery and follow-up. The queue is unchanged at this checkpoint: no open PRs and nine open issues (CLI 1631/1669; Mac 1453/1554/1651/1660/1661/1662/1668). The maintenance release remains worthwhile as V1.57.0 after candidate CI and Nightly follow-up; tty7 and real large-tree filtering remain known evidence gaps.

## Loading and combined release checks

The maintainer approved the centered 2x2 loading mark after testing it in Kaku. Shell and Analyze now share the four centered braille frames; the glyph still takes one terminal column, and existing tick intervals, caller traps, and cancellation paths are unchanged. The shorter frame sequence changes the rotation period intentionally. The shared UI guide records the shape and Shell/Go parity rule.

The combined candidate passed project formatting/checks, targeted UI tests, Go tests, the complete test runner with exit 0 and no TAP skip directives, and native Analyze/Status JSON smoke probes. All seven candidate files stayed byte-identical throughout the complete runner, including its unit, Go, module, integration, and isolated-installation phases. Go 1.26.0 built all four Intel/Apple Silicon release binaries; every binary retains macOS 12.0 as its minimum. The six full-release review angles found no confirmed introduced defect. Candidate remote CI, downloaded Nightly source verification, and formal release assets remain separate delivery checks; local builds do not prove public assets or Homebrew availability.

## Follow-up verification and residual fixes

The maintainer requested fresh whole-code testing, narrow repairs for the three residual reports, and an intermediate-release assessment, then approved commit/push of the verified follow-up. This follow-up does not authorize a new stable tag or publication. The maintainer will send the reporter reply personally; hand back the text after verifying source delivery and leave the email draft unsent.

- Baseline `main` and remote `main` were `f868c189f048844580b51e5955bc89fa50cd6e14`, with a clean worktree. Latest published stable remains `V1.56.1` from 2026-09-28.
- Issue 1666: reproduced an activity-worker batch barrier that leaves free slots idle behind a slow probe. Local sliding-window repair preserves the shared deadline, per-item classifier, result/status identity, concurrency ceiling, and final safety checks. On the same 16-directory read-only fixture, the baseline took 17.288 seconds and probed 12 items; the repair took 7.432 seconds and probed all 16, with no remaining workers. Slow, recent, and failed items remained protected. The reporter's authored-content filtering cost remains unverified.
- Issue 1659: system Bash 3.2 PTY checks return from list, selector, slow metadata finalization, and Ctrl-C. The actual tty7 runtime is unavailable, so the tty7 hang stays deferred with the reporter-confirmed Terminal workaround. An older scan-phase Ctrl-C exit-status limitation (0 instead of 130) is separate from the hang and unchanged.
- Issue 1669: the reporter's diagnostic locates incomplete `/Volumes` discovery (`find` exit 1, mapped to partial scan 3). The logged `[TIMEOUT] Perl fallback, 5s` is backend startup information, not timeout evidence. Because the old diagnostic copied stderr's first line, the actual find error is still absent. Local diagnostics now skip only backend startup lines and retain the first cause line, preserving the refusal codes; the new regression fails before the change and passes after it. Keep the issue open until the inaccessible path or other underlying failure is known. A separate existing safety gap was reproduced: a symlink application root can yield a successful empty `find` listing despite a surviving sibling. The local guard treats that root as unknown in both preview and execution and keeps shared leftovers; it is not a fix for the reported inability to remove leftovers.
- Regression evidence: sliding-window throughput and both symlink-root regression groups fail on the baseline and pass after the repair. An unhandled polling sleep also failed under a bare `set -e` call with real PTY Ctrl-C; the repair drains workers and restores traps before returning 130. The five targeted Bats files passed all 347 tests.
- Two whole-suite runs failed in the same four real-pipeline `clean --dry-run` cases. The runner's explicit Go 1.26 selection made `go env` download a toolchain into each fresh fixture HOME and exceed the bounded resolver probe. An offline probe confirmed the download dispatch, and a Go cache-root fixture shim made all four pass under the same selection. The real-pipeline helper now mocks those unasserted owner probes instead of inheriting the host toolchain. The final whole-suite run passed with exit 0, including unit, Go, module-loading, integration, and installation checks. Project checks and fresh Go race tests also passed. All four architecture-specific binaries were built with Go 1.26 and verified against the macOS 12 minimum; native analyze/status JSON smoke tests passed. The six changed functional/test files stayed byte-identical throughout the final suite.
- The original 1669 email thread and its local diagnostic attachment were matched; a short English reply is saved as an unsent draft in that thread. The maintainer now wants the reply text to send personally. After verified source delivery, hand back one familiar, read-only isolated Nightly command alongside Homebrew to capture the underlying error, without claiming leftover removal is fixed. Leave the draft unsent. No additional testing request is needed for 1659's already-confirmed Terminal workaround.
- Release assessment: 35 non-merge commits since stable comprise 23 fixes, 2 small features, and 10 test/documentation/maintenance changes. A `V1.57.0` maintenance-focused release is worthwhile after final local validation, candidate push, and successful candidate CI. No version bump, tag, release assets, public replies, or closures were made in this follow-up.
- Follow-up queue refresh still has no open PRs and nine open issues (CLI 1631/1669, plus the same seven Mac issues), with no added IDs. Intentional visible changes in this local patch are faster purge activity scheduling, more useful failed-scan `--debug` diagnostics, and retained shared leftovers when an application scan root is a symlink. No new command, flag, setting, cleanup target, or wider deletion matcher was introduced.

## Execution status

The baseline and dispositions below are the original review snapshot. Current execution supersedes their pre-implementation closure recommendations.

- PR 1671 merged as `cf9202dd074fab09c005f26184fc4185f22892d8` after local full tests and successful CI.
- PR 1672 revised on the contributor branch (`7a4340faf4cb80f5ad03de70f023345552c32909`) and merged as `f3b6ea5b3773b9429aa70909593636237dc71ef8`; all nine head checks succeeded.
- PR 1673 has sibling-result regressions and a non-rewriting merge of main (`d4d63bb2947664bdd240e13ac0d6a30eeb6100c0`). Both appended regression groups were retained, combined full tests and all nine CI checks passed. Merged as `3123ea92b8c3decad7bc0101391c2b9c97ef5605`.
- PR 1667 was narrowed on the contributor branch (`55fd21126b80908f5ecf50b784d355e181499da2`). Twenty-six output statements retain their plain text with color and NO_COLOR; project checks, full tests and all nine CI checks passed. Merged as `ae89192875b1aa950e0c9b02b1fe38a5c21c1a5b`.
- Uninstall probe/finalization diagnostics are delivered on main as `cf75d0c3d015a48dfa5f1aef2416221ce223a044`; full tests passed and the downloaded main source was checked byte-for-byte.
- Issue 1659 is closed with the reporter-confirmed built-in Terminal workaround. The maintainer rejected the unnecessary clone-and-diagnose request; that public comment was edited in place to remove it. The tty7-specific hang remains unresolved, not claimed fixed.
- Issue 1666 is closed for Nightly testing of the bounded activity and filtering corrections. The downloaded source contains both fixes. Authored-content filtering remains bounded and potentially expensive; no speedup or complete result on the reporter's real tree is claimed. Reopen if it persists.
- Issue 1669 remains open. The new private diagnostic confirms the Time Machine snapshot permission failure; the approved local repair and its remaining checks are recorded above. Previous diagnostic output alone was not a leftovers-removal fix.
- Issue 1631 remains open for samples; only two public machine reports exist, insufficient for the accepted first-20/three-large-cache threshold.
- The nine original Mac issues were outside this CLI execution. Issues 1650 and 1665 were closed elsewhere during this run (public replies by tw93, respectively Preview 299 and not planned). Remaining Mac IDs: 1453, 1554, 1651, 1660, 1661, 1662, 1668 (7).

Final queue readback on 2026-10-03:

- Initial PR IDs: 1667, 1671, 1672, 1673 (4). Final open PR IDs: none (0); all four are merged. Contributor authors are preserved, and squash messages omit attribution trailers.
- Initial issue IDs: 1453, 1554, 1631, 1650, 1651, 1659, 1660, 1661, 1662, 1665, 1666, 1668, 1669 (13).
- This CLI execution closed 1659 and 1666 (2). Separately, 1650 and 1665 closed elsewhere (2). Final open issue IDs: 1453, 1554, 1631, 1651, 1660, 1661, 1662, 1668, 1669 (9), comprising CLI 1631/1669 (2) and Mac (7). No new IDs appeared.
- Final downloadable main archive at `3123ea92b8c3decad7bc0101391c2b9c97ef5605` matched all ten changed production files and started successfully. Main's combined purge and uninstall diagnostic regressions passed. All four PR heads passed their nine CI checks; post-merge main workflows were still running or queued at readback.
- Public replies and closure states were read back under tw93 for PRs 1667/1671/1672/1673 and issues 1659/1666/1669. The complex 1659 request was replaced in place, not followed by another comment.
- Work continues only when 1669 supplies the diagnostic result or 1631 obtains enough samples. The tty7 hang and bounded large-tree performance are recorded limitations, not claimed fixed beyond the stated workaround/improvements.

Intentional visible changes are size-unit colors in real cleanup/summary and additional --debug diagnostics. There are no new flags, tuning controls, cleanup targets or weakened protections. Stable V1.56.1 is unchanged; no tag or stable release was published.

## Original review baseline

- Repository: `tw93/Mole`, branch `main`, HEAD and remote main both `c430bac637929ebede043df81d3bef319428309c`.
- Worktree was clean before this handoff file was created.
- Latest public CLI release: `V1.56.1`, published 2026-09-28.
- Initial and final PR IDs: 1667, 1671, 1672, 1673 (4).
- Initial and final issue IDs: 1453, 1554, 1631, 1650, 1651, 1659, 1660, 1661, 1662, 1665, 1666, 1668, 1669 (13).
- CLI issues: 1631, 1659, 1666, 1669 (4). Other issues explicitly concern the Mac app (9).
- Final queue refresh found no additions, removals, issue updates, or PR head changes.
- All four PRs have nine completed successful GitHub checks, are mergeable, and allow maintainer edits. This is remote CI evidence, not local test evidence.
- Review covered all PR diffs, issue bodies/comments, relevant production callers, and safety/timeout contracts. No full PR test suite was run in this review.

## PR dispositions

| PR | Decision | Scope and required work |
| --- | --- | --- |
| [1673](https://github.com/tw93/Mole/pull/1673) | Revise contributor branch, then merge | Keep the debug-only correction. Add durable batch-preview regressions for confirmed sibling (0), incomplete scan (3), and failed scan (2), proving unchanged bundle-only plan and no shared teardown. This does not resolve issue 1669. |
| [1671](https://github.com/tw93/Mole/pull/1671) | Merge as written after local verification | Filtering failure now returns its own status and discards partial output instead of repeating discovery with find. Caller excludes failed roots. No concrete blocking defect found. Do not expand into a scan rewrite or larger default timeout. |
| [1672](https://github.com/tw93/Mole/pull/1672) | Revise contributor branch, then merge | Keep bounded activity concurrency and existing deadlines. Fix incomplete result handling, test beyond the first batch, and verify cancellation with real bounded probes. Do not claim this alone completely resolves issue 1666. |
| [1667](https://github.com/tw93/Mole/pull/1667) | Narrow contributor branch, then merge | Keep size-unit coloring in real cleanup and summary; retain existing row text, icons, punctuation, counts, and preview formatting. Avoid a new whole-row renderer just for coloring. Verify unknown/partial sizes and NO_COLOR. |

Contributor branch targets, to be refreshed before any future write:

- 1673: `r266-tech:codex/uninstall-sibling-diagnostics`.
- 1671: `r266-tech:codex/purge-scan-budget`.
- 1672: `r266-tech:codex/purge-activity-window`.
- 1667: `HaraldNordgren:feat/clean-size-colors-real-run`.

### Concrete evidence for PR 1672

The proposed result reader resets only the state when `read` fails, then treats status `1` as `old`. A Bash 3.2 reproduction with a result file containing only `1` without a newline produced `status=1 state=old recent=false`. This can incorrectly preselect a candidate. The final deletion activity recheck still exists, so this is not evidence of a deletion-protection bypass.

Require a complete successful read, a valid status/state pair, and successful worker completion before accepting an old classification. Missing, truncated, malformed, failed, and timed-out records must stay uncertain. Add each case independently, with a positive old control. Add SAFE annotations to the two new scratch-file removals; the existing recursive-deletion audit does not check plain rm -f.

Fixed batches also wait for the slowest member before admitting the next batch. Measure more than four candidates with slow/fast mixing before choosing whether a sliding window is necessary. Keep bounded concurrency and overall budget either way. Cancellation now drains current bounded probes, so verify and report that visible timing change rather than promising immediate exit.

### Scope to remove from PR 1667

The patch intentionally changes more than capacity color: Service Worker preview wording/separators, dry suffixes on some previews, and Simulator capacity parentheses. Those are not deletion regressions, but are unnecessary to the coloring request. Preserve their previous text and change only the capacity ANSI formatting, keeping the success icon green. Do not remove functional protections or accounting.

## CLI issue dispositions

| Issue | Decision | Next step and closure condition |
| --- | --- | --- |
| [1669](https://github.com/tw93/Mole/issues/1669) | Keep open; diagnose | The unreadable-path warning means unknown sibling evidence, not a confirmed sibling. 1673 fixes the misleading debug reason only. Obtain bounded debug evidence at receipt, root enumeration, candidate verification, and deadline failure points. Identify why every app is affected before narrowing any probe scope. Preserve unknown-state retention and final identity/sibling checks. Close only after the actual failure is addressed and a usable delivery path is verified. |
| [1659](https://github.com/tw93/Mole/issues/1659) | Keep open; investigate tty7 | Reporter says --list exits 0, tty7 hangs and ignores Ctrl-C, built-in Terminal works. Observe Finalizing list, metadata-refresh launch, spinner stop/wait, scan return, fingerprint/load, input drain, and selector boundaries. Capture PID/process-group/wait state without app inventory. Reproduce on actual tty7; do not claim spinner is the cause yet. Add a failing regression for the confirmed path before fixing it. |
| [1666](https://github.com/tw93/Mole/issues/1666) | Keep open; accept bounded fix scope | 1671 fixes repeated discovery and misleading stage logs; 1672 improves activity throughput but needs result/cancellation fixes. The expensive authored-content filtering and large-tree end-to-end result remain separately unverified. Compare the same real tree and mode before/after. Do not remove protection walks, increase budgets blindly, add normal skipped counts, retry reminders, or tuning advice. Close only after verified scope is explicit and delivered; keep any remaining throughput problem separately recorded. |
| [1631](https://github.com/tw93/Mole/issues/1631) | Keep open for samples | Accepted threshold is at least 3 of the first 20 machine samples with a cache at least 1 GB. Public thread currently has the original large-cache report and one additional machine sample, insufficient to decide prevalence. Keep E5RT protection. Add only bounded read-only visibility if the threshold is met; close as not planned only after adequate sampling fails the agreed threshold. |

No CLI issue is ready for immediate closure. No PR should currently be rejected as not planned. A merged diagnostic PR alone does not establish that its related issue is fixed.

## Mac app queue, excluded from CLI implementation

These nine items are listed to reconcile the complete public queue, not as source-reviewed Mac findings or closure recommendations.

| Issue | Reported concern | Routing |
| --- | --- | --- |
| [1668](https://github.com/tw93/Mole/issues/1668) | Menu-bar metric spacing and excessive width | Mac UI review; keep open pending rendered geometry validation. |
| [1665](https://github.com/tw93/Mole/issues/1665) | Release notes for different update sources | Mac updater feature assessment; no CLI expansion. |
| [1662](https://github.com/tw93/Mole/issues/1662) | Default selection for deleting app data | Mac product/safety decision; current maintainer comment explicitly leaves the setting under consideration, do not silently close. |
| [1661](https://github.com/tw93/Mole/issues/1661) | Explain app identity/location | Mac installed-app information assessment; keep separate. |
| [1660](https://github.com/tw93/Mole/issues/1660) | Clipped fan RPM label | Mac rendered UI bug investigation, not CLI status. |
| [1651](https://github.com/tw93/Mole/issues/1651) | Xcode preview size differs from cleanup | Mac support investigation; private diagnostic requested, preserve authored/in-use data. |
| [1650](https://github.com/tw93/Mole/issues/1650) | Full analyze refresh leaves nested cached views stale | Mac cache invalidation investigation; do not infer CLI cache regression. |
| [1554](https://github.com/tw93/Mole/issues/1554) | Updates refresh misses Homebrew updates | Mac recurrence, reopened; reporter says private diagnostics sent. Retrieve those before another patch. |
| [1453](https://github.com/tw93/Mole/issues/1453) | Manual fan mode drops back | Mac recurrence, reopened after newer version report; current build/runtime evidence needed, no blind retuning. |

## Original execution order

1. Revise and validate PR 1673, then merge through the contributor PR. Leave 1669 open.
2. Diagnose 1669 at the actual failed probes, then deliver the narrow confirmed fix.
3. Reproduce 1659 in tty7 with minimum stage/process evidence, then fix the confirmed interactive path.
4. Validate and merge 1671, revise/validate/merge 1672, then measure 1666 end to end. Keep unresolved filtering cost explicit.
5. Narrow, render/compare, and validate 1667, then merge.
6. Continue 1631 sampling; decide using the existing threshold, not the maintainer's disk.
7. Review Mac items in the Mac repository as a separate authorized task.

For each implementation: refresh PR head, base, permission, contributor remote, local branch/worktree, and GitHub identity before writing. Preserve attribution, omit AI trailers on merge. Run targeted red/green regressions, project checks, full tests before commit/merge, and required Go/build checks when relevant. Investigate base failures rather than attributing contributor-reported failures to the PR without reproduction.

Before any issue reply/closure, verify the actual source-to-user delivery path. Stable V1.56.1, main, and Nightly are separate claims. Refresh initial/final queue IDs after every execution batch. Update this handoff as items are resolved; remove it when the handoff is no longer needed.
