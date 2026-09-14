#!/usr/bin/env bats

# Tests for remove_file_list batching in lib/uninstall/batch.sh.
# Exercises the batched Trash path (single _mole_move_to_trash_batch call for
# eligible files) and the fallback when the batch helper fails.

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT
}

setup() {
    SANDBOX="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-uninstall-batch.XXXXXX")"
    export SANDBOX
    export MOLE_DELETE_LOG="$SANDBOX/deletions.log"
    export MOLE_TEST_TRASH_DIR="$SANDBOX/Trash"
    export MOLE_TEST_NO_AUTH=1
    export MOLE_DELETE_MODE=trash
    unset MOLE_DRY_RUN
    HOME="$SANDBOX/home"
    mkdir -p "$HOME"
    export HOME
}

teardown() {
    rm -rf "$SANDBOX"
}

prelude() {
    cat <<EOF
set -euo pipefail
export MOLE_DELETE_LOG="$MOLE_DELETE_LOG"
export MOLE_TEST_TRASH_DIR="$MOLE_TEST_TRASH_DIR"
export MOLE_TEST_NO_AUTH=1
export MOLE_DELETE_MODE=trash
export HOME="$HOME"
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/uninstall/batch.sh"
EOF
}

@test "remove_file_list refuses shared XDG roots regardless of display-name casing (#1446)" {
    mkdir -p "$HOME/.Local/bin" "$HOME/.Config" "$HOME/.Cache"
    touch "$HOME/.Local/bin/unrelated-cli" "$HOME/.Config/unrelated-config" "$HOME/.Cache/unrelated-cache"
    local list
    printf -v list '%s\n%s\n%s' "$HOME/.Local" "$HOME/.Config" "$HOME/.Cache"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
remove_file_list "$list" "false"
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"0"* ]]
    [[ -f "$HOME/.Local/bin/unrelated-cli" ]]
    [[ -f "$HOME/.Config/unrelated-config" ]]
    [[ -f "$HOME/.Cache/unrelated-cache" ]]
    [[ ! -d "$MOLE_TEST_TRASH_DIR" ]]
}

@test "remove_file_list batches eligible Trash moves into a single helper call" {
    local f1="$SANDBOX/a.plist"
    local f2="$SANDBOX/b.plist"
    local f3="$SANDBOX/c.plist"
    local f4="$SANDBOX/d.plist"
    local f5="$SANDBOX/e.plist"
    : > "$f1"
    : > "$f2"
    : > "$f3"
    : > "$f4"
    : > "$f5"
    local list
    printf -v list '%s\n%s\n%s\n%s\n%s' "$f1" "$f2" "$f3" "$f4" "$f5"

    local count_file="$SANDBOX/batch_calls"
    : > "$count_file"

    # Stub the batch helper to (1) record how many times it was called and
    # how many paths each call covered, (2) emulate the real test-harness
    # behavior by mv'ing each path into MOLE_TEST_TRASH_DIR. This lets the
    # test assert both "called once" and "every file landed in trash".
    run /bin/bash --noprofile --norc <<EOF
$(prelude)
_mole_move_to_trash_batch() {
    mkdir -p "\$MOLE_TEST_TRASH_DIR"
    printf 'call %d\n' "\$#" >> "$count_file"
    local p dest
    for p in "\$@"; do
        dest="\$MOLE_TEST_TRASH_DIR/\$(basename "\$p").stub.\$RANDOM"
        mv "\$p" "\$dest" 2>/dev/null || return 1
    done
    return 0
}
remove_file_list "$list" "false"
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"5"* ]] # remove_file_list echoes count

    # All five files moved to the stub trash dir.
    local in_trash
    in_trash=$(find "$MOLE_TEST_TRASH_DIR" -type f | wc -l | tr -d ' ')
    [ "$in_trash" -eq 5 ]
    for f in "$f1" "$f2" "$f3" "$f4" "$f5"; do
        [[ ! -e "$f" ]] || return 1
    done

    # Single batch invocation, with all five paths.
    local call_count
    call_count=$(wc -l < "$count_file" | tr -d ' ')
    [ "$call_count" -eq 1 ]
    grep -q '^call 5$' "$count_file"

    # Audit log records one ok line per moved path.
    local ok_lines
    ok_lines=$(awk -F'\t' '$4 == "ok" && $2 == "trash"' "$MOLE_DELETE_LOG" | wc -l | tr -d ' ')
	[ "$ok_lines" -eq 5 ]
}

@test "Trash batches refresh live-owner evidence before each move" {
	local first_cache="$HOME/Library/Caches/com.example.One"
	local second_cache="$HOME/Library/Caches/com.example.Two"
	mkdir -p "$first_cache" "$second_cache" "$HOME/.cache/mole"
	printf 'one\n' > "$first_cache/data"
	printf 'two\n' > "$second_cache/data"
	local ps_count="$SANDBOX/ps-count"
	: > "$ps_count"

	run env PROJECT_ROOT="$PROJECT_ROOT" PS_COUNT="$ps_count" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
ps() {
	printf 'x' >> "$PS_COUNT"
	local calls
	calls=$(wc -c < "$PS_COUNT" | tr -d ' ')
	printf '  PID  PPID COMM ARGS\n'
	if [[ $calls -ge 2 ]]; then
		printf '9000 1 /Applications/ExampleTwo /Applications/ExampleTwo --bundle com.example.Two\n'
	fi
}
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/uninstall/batch.sh"
remove_file_list "$(printf '%s\n%s\n' \
	"$HOME/Library/Caches/com.example.One" \
	"$HOME/Library/Caches/com.example.Two")" false
printf 'PS_CALLS=%s ONE=%s TWO=%s\n' \
	"$(wc -c < "$PS_COUNT" | tr -d ' ')" \
	"$([[ -e "$HOME/Library/Caches/com.example.One" ]] && printf yes || printf no)" \
	"$([[ -e "$HOME/Library/Caches/com.example.Two" ]] && printf yes || printf no)"
EOF

	[ "$status" -eq 0 ] || return 1
	[[ "$output" == *"PS_CALLS=3 ONE=no TWO=yes"* ]] || return 1
}

@test "remove_file_list preserves unmoved paths when the guarded batch helper fails" {
    local f1="$SANDBOX/x.plist"
    local f2="$SANDBOX/y.plist"
    : > "$f1"
    : > "$f2"
    local list
    printf -v list '%s\n%s' "$f1" "$f2"

    local trace="$SANDBOX/trace"
    : > "$trace"

    # A failed identity-bound batch must not hand the same stale lexical paths
    # to a second sink. The files stay in place for manual review.
    run /bin/bash --noprofile --norc <<EOF
$(prelude)
_mole_move_to_trash_batch() { return 1; }
mole_delete() {
    printf 'mole_delete %s\n' "\$1" >> "$trace"
    return 99
}
remove_file_list "$list" "false"
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"0"* ]] || return 1
    [[ -e "$f1" && -e "$f2" ]] || return 1
    [[ ! -s "$trace" ]]
}

@test "guarded Trash batch rejects an ancestor swapped after collection" {
    local base="$SANDBOX/swap-parent"
    local original_parent="$SANDBOX/original-parent"
    local outside_parent="$HOME/Documents/OutsideParent"
    local target="$base/cache"
    mkdir -p "$target" "$outside_parent/cache"
    touch "$target/OWNED_SENTINEL" "$outside_parent/cache/OUTSIDE_SENTINEL"
    local list="$target"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
eval "\$(declare -f _mole_snapshot_path_identity | sed '1s/_mole_snapshot_path_identity/_real_mole_snapshot_path_identity/')"
snapshot_calls=0
_mole_snapshot_path_identity() {
    snapshot_calls=\$((snapshot_calls + 1))
    if [[ \$snapshot_calls -eq 2 ]]; then
        mv "$base" "$original_parent"
        ln -s "$outside_parent" "$base"
    fi
    _real_mole_snapshot_path_identity "\$1"
}
mole_delete() { echo "UNEXPECTED_FALLBACK:\$1"; return 99; }
remove_file_list "$list" "false"
[[ -f "$outside_parent/cache/OUTSIDE_SENTINEL" ]] || exit 1
[[ -f "$original_parent/cache/OWNED_SENTINEL" ]]
EOF

    [ "$status" -eq 0 ] || {
        echo "$output"
        return 1
    }
    [[ "$output" == *"0"* ]] || return 1
    [[ "$output" != *"UNEXPECTED_FALLBACK"* ]] || return 1
    [[ ! -e "$MOLE_TEST_TRASH_DIR/cache" ]]
}

@test "_mole_move_to_trash_batch returns 1 when trash CLI is missing under MOLE_TEST_NO_AUTH" {
    local f1="$SANDBOX/p.plist"
    : > "$f1"

    # Drop MOLE_TEST_TRASH_DIR so we exercise the real helper path; the
    # MOLE_TEST_NO_AUTH guard must fail closed before any AppleScript runs.
    run /bin/bash --noprofile --norc <<EOF
set -euo pipefail
export MOLE_TEST_NO_AUTH=1
unset MOLE_TEST_TRASH_DIR
source "$PROJECT_ROOT/lib/core/common.sh"
_mole_move_to_trash_batch "$f1"
EOF

    [ "$status" -ne 0 ]
    [[ -e "$f1" ]]
}

@test "remove_file_list with sudo paths bypasses batching and routes per-file" {
    local f1="$SANDBOX/sudo_a.plist"
    local f2="$SANDBOX/sudo_b.plist"
    : > "$f1"
    : > "$f2"
    local list
    printf -v list '%s\n%s' "$f1" "$f2"

    local batch_count="$SANDBOX/batch_count"
    local fallback_count="$SANDBOX/fallback_count"
    : > "$batch_count"
    : > "$fallback_count"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
_mole_move_to_trash_batch() {
    printf '1\n' >> "$batch_count"
    return 0
}
mole_delete() {
    printf '%s\n' "\$1" >> "$fallback_count"
    rm -f "\$1"
    return 0
}
remove_file_list "$list" "true"
EOF

    [ "$status" -eq 0 ]

    # Sudo path must avoid the batch helper entirely.
    [[ ! -s "$batch_count" ]] || return 1

    local n
    n=$(wc -l < "$fallback_count" | tr -d ' ')
    [ "$n" -eq 2 ]
}

@test "remove_file_list stops after an interrupted per-file delete" {
    local first="$SANDBOX/interrupt-first.plist"
    local second="$SANDBOX/interrupt-second.plist"
    : > "$first"
    : > "$second"
    local list
    printf -v list '%s\n%s' "$first" "$second"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
_mole_path_requires_direct_trash() { return 0; }
delete_calls=0
mole_delete() {
    delete_calls=\$((delete_calls + 1))
    printf 'DELETE_CALL:%s\n' "\$1"
    return 130
}
rc=0
remove_file_list "$list" "false" || rc=\$?
printf 'RC=%s CALLS=%s\n' "\$rc" "\$delete_calls"
EOF

    [ "$status" -eq 0 ] || return 1
    [[ "$output" == *"RC=130 CALLS=1"* ]] || return 1
    [[ "$output" == *"DELETE_CALL:$first"* ]] || return 1
    [[ "$output" != *"DELETE_CALL:$second"* ]] || return 1
    [[ -e "$first" ]] || return 1
    [[ -e "$second" ]]
}

@test "remove_file_list routes Microsoft Word app data per-file and batches ordinary leftovers" {
    local container="$HOME/Library/Containers/com.microsoft.Word"
    local group_container="$HOME/Library/Group Containers/UBF8T346G9.Office"
    local app_scripts="$HOME/Library/Application Scripts/com.microsoft.Word"
    local ordinary="$HOME/Library/Preferences/com.microsoft.Word.plist"
    mkdir -p "$container" "$group_container" "$app_scripts" "$(dirname "$ordinary")"
    : > "$ordinary"
    local list
    printf -v list '%s\n%s\n%s\n%s' "$container" "$group_container" "$app_scripts" "$ordinary"

    local direct_trace="$SANDBOX/direct.log"
    local batch_trace="$SANDBOX/batch.log"
    : > "$direct_trace"
    : > "$batch_trace"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
export MOLE_UNINSTALL_MODE=1
_mole_move_to_trash_batch() {
    printf '%s\n' "\$@" >> "$batch_trace"
    return 0
}
mole_delete() {
    printf '%s|%s\n' "\$1" "\${2:-false}" >> "$direct_trace"
    return 0
}
trash() {
    echo "trash CLI must not be called" >&2
    return 99
}
osascript() {
    echo "Finder must not be called" >&2
    return 98
}
remove_file_list "$list" "false"
EOF

    [ "$status" -eq 0 ]
    [ "$(wc -l < "$direct_trace" | tr -d ' ')" -eq 3 ]
    grep -qF "$container|false" "$direct_trace"
    grep -qF "$group_container|false" "$direct_trace"
    grep -qF "$app_scripts|false" "$direct_trace"
    [ "$(wc -l < "$batch_trace" | tr -d ' ')" -eq 1 ]
    grep -qxF "$ordinary" "$batch_trace"
    [[ "$output" != *"trash CLI must not be called"* ]] || return 1
    [[ "$output" != *"Finder must not be called"* ]]
}
