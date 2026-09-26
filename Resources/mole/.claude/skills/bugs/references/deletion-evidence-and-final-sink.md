# Deletion evidence and final sink

Read this reference when a candidate, protection rule, owner probe, dry-run branch, fallback, or deletion helper changes.

## 1. Weak name evidence authorizes deletion

A display name, bundle-id prefix, TeamID prefix, or substring glob eventually matches a neighbour. Exact bundle id or exact app path is evidence; vendor prefixes, generic words, and fallback wildcards are not.

Past shapes:

- `find_app_files` derived `~/.config/<name>` from a GUI display name, so uninstalling Claude.app removed Claude Code CLI state. Case-insensitive APFS widened the collision (`3fa3eb5c`).
- `${bundle_id}*.plist` let `com.foo` match `com.foobar.plist` (`5498edd1`).
- Substring teardown removed a surviving `Foo-beta.app` sibling while uninstalling `Foo.app` (`ec1cd647`).
- TeamID-prefix fallbacks in PR #874 and #875 were merged and then reverted (`229bd0f9`, `bc7f4c0a`).
- A failed `brew info --cask` plus a basename or copied-bundle match is not ownership. The `#1558` Caskroom fallback needs the unique installed cask's app symlink pointing at the exact selected app, rechecked after the lookup. Timeout and signal still abort. `#1579` kept that bar for binary-only casks: name the refused app and send the user to `brew info --cask` instead of accepting `brew list --cask` as proof.

Probe the class:

```bash
command grep -rnE '\*\$\{?(app_name|bundle_id|name)\}?\*|\$\{bundle_id\}\*' lib/ bin/
```

For every hit, name the narrowest fact authorizing the sink. Review primary and fallback branches separately.

## 2. One probe decides existence or idleness

Every owner predicate must distinguish `present`, `absent`, and `could not tell`. Timeout, permission denial, missing metadata, or incomplete discovery is unknown, never absent.

Past shapes:

- `mdfind` missed Homebrew casks and embedded SMJobBless helpers (`6a055de4`).
- `command -v` plus LaunchAgents missed a GUI Proton Mail Bridge owner and called `~/.bridge` orphaned (`28ee58c9`).
- Any UP `utun*` interface was treated as VPN, including iCloud Private Relay (`37a446c9`).
- `brew list mole` answered an ownership question but reset the user's sudo timestamp. Replacing it with a Cellar check removed the side effect, then initially missed custom prefixes until the prefix was also derived from the installed brew path (`cb4a3d66`, `73f89841`).
- A `playwright-cli` daemon is normally `ppid 1` for the life of an active session, because `cli-client/session.js` spawns `cliDaemon.js` detached and unref'd; matching on it kills a live session. Leaked automation browsers are a `playwright_chromiumdev_profile` root whose `pgrep -f` returns exactly 1. Any other status is unknown and keeps the profile (`9e67a3ff`, `#1518`).

```bash
command grep -rn 'mdfind' lib/ bin/ | command grep -v run_with_timeout
```

List every legitimate location or representation of the subject. Prefer filesystem facts when they answer the question without starting an owner tool, but verify every supported installation layout. A timed-out producer may fall back to a separate complete source; it may not authorize deletion from a partial prefix.

A memoized probe answer is only as good as the state it was taken in. `_mole_complete_lsof_mode` caches `direct`, `sudo`, or `unknown` in `_MOLE_COMPLETE_LSOF_MODE` on its first call and has no reset. `start_cleanup` in `bin/clean.sh` adopts or prompts for sudo before `perform_cleanup` runs any step, and `lib/uninstall/batch.sh` settles its sudo session through `ensure_sudo_session` before `_batch_execute_removals` reaches its first `remove_file_list`. Two separate design rounds proposed probing during the uninstall preview, which runs before that gate, to decide what to show. The memo would have frozen at `unknown`, and the runs where admin is available, brew casks and system apps, would have started keeping caches they delete today, silently and with no test covering it. The mode probe itself is immune to the `MO_DEBUG` stderr contamination fixed in other probes, because it positively matches `p1` and `u0` lines rather than testing the buffer for emptiness; that was verified with a trace-prefixed fixture and a non-root positive control.

Owner-process attribution reads each executable from a second `ps -axo pid=,comm=` read, where `comm` is the last column and so is never cut to 16 bytes. `_mole_load_process_table` appends it to the line after `\037`, and `_mole_process_line_belongs_to_other_app` resolves the bundle from that path, which survives rewritten argv and paths with spaces. A pid missing from that read keeps the argv heuristic, which stays busy for a line it cannot place. Earlier fixes to the text-splitting heuristic: `24414873`, `45a19b70`, `54958a95`, `2e4cfaba`.

## 3. A guard exists on only one path

Call-site protection is forgotten by the next caller. Prefer funnel-level policy in `validate_path_for_deletion`, `safe_remove`, `mole_delete`, `safe_find_delete`, or the closest shared owner guard.

Past shapes:

- `should_protect_path` ran only in real mode, so dry-run promised work the real run refused (`cfe14601`).
- A caller forgot the whitelist until it moved beside the protection gate in the shared `find` sinks (`5498edd1`).
- A Raycast exclusion existed outside the actual `find` predicates (`452e194d`).
- `_safe_clean_impl` consulted a delete guard only in real mode, so preview registered and counted items an active-process guard refused (`3f42ad39`).

Enumerate every caller of the protection helper, then every sink, and diff the lists. Dry-run and real mode must compute the same eligibility plan. Run target-specific guards after missing, protected, whitelisted, and compiled-model candidates are filtered, but before preview registration or deletion.

## Final-sink matrix

For each destructive family, fill this matrix from live code:

| Stage | Required evidence | Failure behavior |
|---|---|---|
| Discovery | Exact supported root and complete scan | Incomplete result is discarded or marked partial |
| Cheap filters | Missing, protected, whitelist, compiled model | Candidate omitted without expensive probes |
| Owner probe | Process and open-handle tri-state | Live or unknown refuses |
| Size/metadata | Bounded, no authorization reuse | Timeout is observable; no false reclaimed bytes |
| Final re-probe | Owner state after slow work | New live or unknown state refuses |
| Identity rebind | Physical parent plus target identity | Rename, replace, or symlink change refuses |
| Sink | Shared safe helper and preserved confirmation | No raw fallback delete |
| Accounting | Only completed mutation counts | Refused and failed items remain excluded |

Container, SQLite, helper-app, and privileged paths require the final re-probe and identity rebind immediately before the sink. A discovery snapshot is not an ownership lease.

Signals and cancellations are part of the evidence chain. Preserve statuses `>=128`, keep cancellation sticky across best-effort callers, and prevent any later sink from running after cancellation.

## 13. A mutation target is accepted as a discovery container

Recursive discovery must not descend through the artifact it is meant to offer. If `node_modules`, `vendor`, or `Pods` is accepted as a project container, package-internal manifests become false project roots, the scan starts below the real target, and nested `dist` or `build` directories reach the delete list. The parent artifact is never available for nested-target collapsing, so removing the children can leave the package manager believing the incomplete tree is installed (#1459). In that report a stray `~/node_modules` matched the container probe on its first package's `package.json`, every package became a project root, and `filter_nested_artifacts` never saw the parent to collapse into, so package-internal `dist/` and `build/` reached the delete list. Removing them left `package.json` in place, npm reported the tree as up to date, and recovery needed `npm ci`, the network restore purge promises never to require.

Treat the target list itself as the excluded-container namespace instead of maintaining a second hand-written denylist; `vendor/` and `Pods/` have the same shape as `node_modules/`. Review every scan-root entry point separately: maintainer defaults, user-configured roots, automatic discovery, and the consumer of discovery may intentionally have different trust contracts. In `lib/clean/project.sh` the other three are a maintainer-authored default list, the user config file, and the consumer of discovery, so the `is_project_container` probe is the whole surface. Mole's explicit `purge_paths` is the escape hatch for a real project whose basename happens to match a target, which is why the fix needed no new flag; do not weaken automatic discovery to support it.

A regression needs a package-shaped descendant whose internal artifact would be offered before the fix. Assert that the parent container is not entered and that the explicit configured-root path remains reachable.

## 14. Owner metadata is not automatically deletion authority

A journal records events, a registry records one current view, and a cache records a previous observation. None is a complete deletion inventory unless the owner documents that contract and coordinates concurrent mutation.

The editor-extension cycle showed both halves of the trap. `.obsolete` is a removal journal, so its emptiness does not prove every on-disk extension is live. But reconciling the directory against profile registries was still unsafe: a union keep-set can miss an unknown profile, newly written registration, or owner mutation between the scan and sink. A stopped-process probe narrows activity; it does not create a shared lock or an atomic owner snapshot. The safe product boundary returned to exact owner-written obsolete markers rather than treating absence from a reconstructed inventory as permission to delete.

Before deriving deletion from owner metadata, answer:

- Does the owner call the data an inventory, journal, cache, or best-effort index?
- Can every supported profile, installation, and concurrent writer be enumerated?
- Does Mole share the owner's lock, generation, or machine-readable garbage-collection command?
- Can a new owner reference appear after the keep-set is built but before the sink?
- Is interruption equivalent to a cache miss, or can it leave installed/session/authored state incomplete?

If completeness or synchronization is not guaranteed, use only exact owner-authored removal markers, call an owner-supported cleanup command, offer a documented whole-cache reset when its recovery contract permits it, or leave the target alone. Adding more inferred keep sources does not turn an incomplete universe into authority.

## 18. A sandbox well-known path is not app-private leftover

macOS creates every App Sandbox container with well-known names under `Data/`. Those names do not mean the bytes are the app's rebuildable cache.

- `Data/Downloads`, `Data/Desktop`, `Data/Pictures`, `Data/Music`, and `Data/Movies` are usually symbolic links to the real user folders. Apple's sandbox docs say the container includes those links, and access to the resolved location needs the matching entitlement plus TCC.
- `Data/Documents` is a real directory inside the container. It holds user documents the app wrote without going through `~/Documents`.
- On a current Mac, every container `Data/Downloads` and `Data/Desktop` resolved to the home-folder symlink; every `Data/Documents` was a real in-container directory.

`#1578` asked Mole to clean `~/Library/Containers/com.kingsoft.wpsoffice.mac/Data/Downloads/*` while leaving that Downloads directory itself. WPS ships `com.apple.security.files.downloads.read-write`, so writes through that path land in the user's `~/Downloads`. Kingsoft's own download location is the user-set `文档/WPS/下载`, not this alias. Clearing the glob would empty the real Downloads folder.

The same illusion shows up as "container leftover" proposals for Desktop and Pictures. The lexical path sits under `Library/Containers`, so it looks disposable. Physically it is user documents.

Before adding a container cleanup target:

1. Resolve the path with `readlink` or `pwd -P`. If it lands in `~/Downloads`, `~/Desktop`, or another user document root, stop.
2. Classify the remaining interior: `Data/Library/Caches` and `Data/tmp` are the existing rebuildable carve-outs; `Data/Documents` and `Data/Library/Application Support` are user or mixed state until a measured non-target list says otherwise.
3. Apply the Product Decision Filter. No measured rebuildable bytes, or no explicit excluded siblings, means the target stays out of default `clean`.

`should_protect_path` already blankets `~/Library/Containers` interiors as user data. Do not punch a hole for a well-known name that Apple aliased to the home folder. A regression for this class asserts the resolved destination, not only that the lexical container path exists.
