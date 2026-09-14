# State, accounting, and progress

Read this reference when a fix changes cached derivations, displayed totals, preview accounting, or the timing of terminal feedback.

## 8. Persisted derived data outlives its algorithm

Changing a computation without invalidating its cache leaves the old result shipping after the source fix.

`7a996aa5` is the representative shape: a hardlink-dedup change bumped the cache schema and marked dedup-dependent subtrees non-cacheable. Analyze has also needed expiry, mutation invalidation, and a manual-refresh path that bypasses nested caches.

For every persisted derivation, identify:

- schema version;
- TTL, when age matters;
- invalidation for every input mutation;
- whether a caller consumes the value as proof of absence;
- whether the verification run is reading data from a previous release.

A TTL proves only that an entry is not too old. It never proves completeness. `pkg_receipt_nonstandard_app_paths --require-complete` once accepted an hour-old receipt cache as proof no sibling install existed. Rechecking cached paths could remove stale entries but could not discover a newly installed owner. The fix keyed completeness to a fingerprint of `pkgutil --pkgs`, so new evidence invalidates the entry (`b4f00651`).

When a caller uses cached data to authorize deletion, either bypass the cache or bind it to a fingerprint of all evidence whose appearance would change the verdict.

## 9. Two paths compute one number differently

Any value rendered twice will disagree eventually: dry-run preview versus final summary, item count versus raw target count, subtree size versus `du`, or decimal versus binary units.

Find every producer and choose one definition. Prefer passing the measured value into the sink or renderer over recomputing it. Then compare the two rendered surfaces in a regression test rather than pinning an unrelated literal.

Accounting rules:

- Filtered, refused, timed-out, failed, or disappeared candidates add neither cleaned items nor reclaimed bytes.
- Dry-run and real mode use the same eligible candidates; only the action differs.
- A size timeout may produce an explicit unknown or partial total, never a fabricated zero presented as complete.
- Large candidate fast paths may skip precise per-item sizing only when the output says the total is partial or not scanned.
- Hardlinks are counted according to one named policy across subtree and summary paths.

`tests/clean_core.bats` contains the preview-versus-summary pattern. Sub-megabyte rounding to zero and per-link hardlink counting belong to this family too.

## 10. Silence is read as a freeze

Slow work outside the spinner window looks hung even when it is bounded. A removal loop once stopped its spinner before doing the expensive work (`8f064707`); dotdir, login-item, System Data, and large-file scans have had the same shape.

Walk the complete rendered section and time every operation over roughly one second. The Mole rhythm is:

```text
section title
loading state
content
one trailing blank line
```

The spinner stops immediately before output that would otherwise be overwritten, then restarts if more silent work follows. A timeout warning is not a substitute for progress during a healthy slow scan.

Performance work needs two receipts:

1. a bounded microbenchmark or call-count invariant that isolates the changed path;
2. an end-to-end command timing under the same mode and machine conditions.

Do not optimize by caching directory sizes: APFS does not propagate descendant mtime to a parent. Optimize absent targets, duplicated owner-tool launches, report-only sizing, and wrong-scope scans. For destructive work, keep final owner probes and identity rebinding even if they are the expensive part.

## 16. Async generations and sample freshness are one contract

An asynchronous result can be valid when it is produced and stale when it arrives. Tag every request with a monotonically changing generation or probe ID, carry it in the result message, and apply the result only to the matching generation. Increment the generation when a refresh or navigation transition creates a new request, not merely when a view repaints.

Test the lifecycle in both directions. An older result must not overwrite a newer refresh. A matching result that arrives while the user is in drill-down may still be worth retaining, and returning to Overview must schedule a new probe rather than displaying the old result as freshly measured. This is why an async Time Machine count needs refresh, leave, return, and out-of-order cases rather than one happy-path command test.

Cached metrics use a parallel contract. Treat related fields as one atomic sample:

```text
value group + collected_at + stale + completeness
```

On a transient refresh failure, return the error but keep the last successful group visible with its original collection time and `stale=true`. Do not combine old values with the new refresh time, clear only half the group, or turn unmeasured data into a measured zero. A later successful sample replaces the whole group and resets stale to false. Status process rows, zombie count, parent attribution, and parent completeness are one such group.

Every serializer and fast/full/watch path must preserve the same distinction among fresh data, stale last-known-good data, measured zero, and never measured. A cache test is incomplete if it checks only the first collection and not the next frame or failed refresh that consumes it.
