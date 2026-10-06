#!/usr/bin/env bats

load helpers/common

# Tests for mole_delete in lib/core/file_ops.sh.
# Exercises permanent mode (default), trash mode (via MOLE_TEST_TRASH_DIR
# so Finder is never invoked), dry-run, and the deletions log.

setup_file() {
    mole_test_setup_project_root
}

setup() {
    SANDBOX="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-mole-delete.XXXXXX")"
    export SANDBOX
    export MOLE_DELETE_LOG="$SANDBOX/deletions.log"
    export MOLE_TEST_TRASH_DIR="$SANDBOX/Trash"
    export MOLE_TEST_NO_AUTH=1
    unset MOLE_DELETE_MODE
    unset MOLE_DRY_RUN
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
source "$PROJECT_ROOT/lib/core/common.sh"
EOF
}

# Exercise the real result handling with only a sandboxed AppleScript fixture.
run_finder_result_fixture() {
    mkdir -p "$SANDBOX/FinderFixture.app"
    run env PROJECT_ROOT="$PROJECT_ROOT" FIXTURE_RC="$1" FIXTURE_MOVE="${2:-0}" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
fixture="$SANDBOX/FinderFixture.app"
_mole_path_is_application_bundle() { [[ "$1" == "$fixture" ]]; }
_mole_trash_target_still_safe() { [[ "$1" == "$fixture" ]]; }
_mole_owned_path_still_valid() { [[ "$1" == "$fixture" ]]; }
debug_log() { printf '%s\n' "$*" >> "$SANDBOX/finder-debug.log"; }
run_with_timeout() {
    [[ $# -eq 4 && "$1" == "$MOLE_TIMEOUT_DISK_VERIFY_SEC" && "$2" == osascript && "$3" == - && "$4" == "$fixture" ]] || return 97
    shift
    "$@"
}
osascript() {
    [[ $# -eq 2 && "$1" == - && "$2" == "$fixture" ]] || return 98
    cat > "$SANDBOX/finder-script"
    printf 'FINDER_STDOUT_MUST_STAY_HIDDEN\n'
    printf 'Finder fixture diagnostic (-1743)\n' >&2
    if [[ "$FIXTURE_MOVE" == 1 ]]; then
        mv "$fixture" "$SANDBOX/MovedFixture.app"
    fi
    return "$FIXTURE_RC"
}
rc=0
_mole_move_app_to_trash_via_finder "$fixture" || rc=$?
printf 'RC=%s\n' "$rc"
EOF
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    [[ "$output" != *"FINDER_STDOUT_MUST_STAY_HIDDEN"* ]] || return 1
    [[ "$output" != *"Finder fixture diagnostic"* ]] || return 1
    [[ -s "$SANDBOX/finder-script" ]]
}

@test "mole_delete defaults to permanent mode and removes the target" {
    local victim="$SANDBOX/victim"
    mkdir -p "$victim"
    : > "$victim/keep.txt"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
mole_delete "$victim"
EOF

    [ "$status" -eq 0 ]
    [[ ! -e "$victim" ]] || return 1
    # Trash dir must remain empty in permanent mode.
    [[ -z "$(ls -A "$MOLE_TEST_TRASH_DIR" 2> /dev/null || true)" ]]
}

@test "safe_remove final sink guard preserves timeout and signal cancellation" {
    local victim="$SANDBOX/final-guard-victim"
    mkdir -p "$victim"
    : > "$victim/keep.txt"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
export MOLE_CURRENT_COMMAND=clean
guard_rc=0
final_guard() { return "\$guard_rc"; }
_MOLE_SAFE_REMOVE_FINAL_GUARD=final_guard
for guard_rc in 124 130; do
    MOLE_CLEAN_CANCEL_STATUS=0
    set +e
    safe_remove "$victim" true 1
    actual_rc=\$?
    set -e
    printf 'GUARD:%s ACTUAL:%s CANCEL:%s\n' \
        "\$guard_rc" "\$actual_rc" "\$MOLE_CLEAN_CANCEL_STATUS"
done
[[ -d "$victim" ]]
EOF

    [ "$status" -eq 0 ] || {
        echo "$output"
        return 1
    }
    [[ "$output" == *"GUARD:124 ACTUAL:124 CANCEL:124"* ]] || return 1
    [[ "$output" == *"GUARD:130 ACTUAL:130 CANCEL:130"* ]] || return 1
    [[ -d "$victim" ]]
}

@test "safe_remove rebinds identity after a final sink guard" {
    local victim="$SANDBOX/final-guard-replaced"
    local original="$SANDBOX/final-guard-original"
    mkdir -p "$victim"
    : > "$victim/old.txt"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
_mole_snapshot_path_identity "$victim"
expected_parent="\$_MOLE_PATH_SNAPSHOT_PARENT"
expected_parent_id="\$_MOLE_PATH_SNAPSHOT_PARENT_ID"
expected_target_id="\$_MOLE_PATH_SNAPSHOT_TARGET_ID"
final_guard() {
    mv "\$1" "$original"
    mkdir -p "\$1"
    : > "\$1/replacement.txt"
}
_MOLE_SAFE_REMOVE_FINAL_GUARD=final_guard
set +e
safe_remove "$victim" true 1 "" \
    "\$expected_parent" "\$expected_parent_id" "\$expected_target_id"
actual_rc=\$?
set -e
printf 'RC:%s ORIGINAL:%s REPLACEMENT:%s\n' \
    "\$actual_rc" "\$(test -f "$original/old.txt" && echo kept || echo missing)" \
    "\$(test -f "$victim/replacement.txt" && echo kept || echo missing)"
EOF

    [ "$status" -eq 0 ] || {
        echo "$output"
        return 1
    }
    [[ "$output" == *"RC:1 ORIGINAL:kept REPLACEMENT:kept"* ]]
}

@test "mole_delete trash mode moves the target instead of rm -rf" {
    local victim="$SANDBOX/victim_trash"
    mkdir -p "$victim"
    printf 'payload' > "$victim/data.txt"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
export MOLE_DELETE_MODE=trash
mole_delete "$victim"
EOF

    [ "$status" -eq 0 ]
    [[ ! -e "$victim" ]] || return 1
    # Something landed in the stub trash dir.
    [[ -n "$(ls -A "$MOLE_TEST_TRASH_DIR" 2> /dev/null || true)" ]]
}

@test "mole_delete moves sudo-required paths to invoking user Trash" {
    local victim="$SANDBOX/victim_sudo_trash"
    local fake_bin="$SANDBOX/bin"
    local fake_home="$SANDBOX/home"
    local trace="$SANDBOX/trace.log"

    mkdir -p "$fake_bin" "$fake_home"
    mkdir -p "$victim"
    printf 'payload' > "$victim/data.txt"

    cat > "$fake_bin/trash" <<'SH'
#!/bin/bash
printf 'trash %s\n' "$*" >> "$MOLE_TEST_TRACE"
exit 99
SH
    cat > "$fake_bin/sudo" <<'SH'
#!/bin/bash
printf 'sudo %s\n' "$*" >> "$MOLE_TEST_TRACE"
if [[ "${1:-}" == "-n" ]]; then
    shift
fi
"$@"
SH
    cat > "$fake_bin/osascript" <<'SH'
#!/bin/bash
printf 'osascript %s\n' "$*" >> "$MOLE_TEST_TRACE"
exit 98
SH
    chmod +x "$fake_bin/trash" "$fake_bin/sudo" "$fake_bin/osascript"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
unset MOLE_TEST_TRASH_DIR
unset MOLE_TEST_NO_AUTH
export MOLE_DELETE_MODE=trash
export PATH="$fake_bin:\$PATH"
export HOME="$fake_home"
export MOLE_TEST_TRACE="$trace"
_mole_privileged_path_has_mutable_ancestor() { return 1; }
_mole_create_privileged_trash_stage() {
    local stage="$SANDBOX/stage-sudo-trash"
    mkdir -p "\$stage"
    printf '%s\n' "\$stage"
}
mole_delete "$victim" true
EOF

    [ "$status" -eq 0 ]
    [[ ! -e "$victim" ]] || return 1
    [[ -d "$fake_home/.Trash/$(basename "$victim")" ]] || return 1
    [[ "$(grep -c '^sudo -n /bin/mv ' "$trace" 2> /dev/null || true)" -eq 1 ]] || return 1
    [[ "$(grep -c '^sudo -n trash ' "$trace" 2> /dev/null || true)" -eq 0 ]] || return 1
    [[ "$(grep -c '^trash ' "$trace" 2> /dev/null || true)" -eq 0 ]] || return 1
    [[ "$(grep -c '^osascript ' "$trace" 2> /dev/null || true)" -eq 0 ]] || return 1
    # The per-item stage lives inside a root-owned 0711 parent, so an
    # unprivileged rmdir cannot unlink it and would leak one directory per move.
    [[ "$(grep -c "^sudo -n /bin/rmdir $SANDBOX/stage-sudo-trash\$" "$trace" 2> /dev/null || true)" -eq 1 ]] || return 1
    # The shared staging root stays: removing it raced with concurrent runs.
    [[ "$(grep -c 'rmdir /Library/MoleTrashStaging' "$trace" 2> /dev/null || true)" -eq 0 ]] || return 1
    [[ ! -d "$SANDBOX/stage-sudo-trash" ]] || return 1
    # -x stops the recursive chown at a mount point nested inside the payload;
    # the same-device gate only covers the payload root.
    [[ "$(grep -c '^sudo -n /usr/sbin/chown -Rhx ' "$trace" 2> /dev/null || true)" -eq 1 ]] || return 1

    local status_col
    status_col=$(awk -F'\t' 'END { print $4 }' "$MOLE_DELETE_LOG")
    [ "$status_col" = "ok" ]
}

@test "sudo Trash ownership refusal keeps the item and clears its empty stage" {
    local victim="$SANDBOX/owned-agent.plist"
    local stage="$SANDBOX/stage-refused-agent"
    local fake_bin="$SANDBOX/bin"
    mkdir -p "$fake_bin" "$SANDBOX/home"
    printf 'original\n' > "$victim"
    cat > "$fake_bin/sudo" <<'SH'
#!/bin/bash
[[ "${1:-}" == "-n" ]] && shift
"$@"
SH
    chmod +x "$fake_bin/sudo"

    run env PROJECT_ROOT="$PROJECT_ROOT" SANDBOX="$SANDBOX" \
        MOLE_DELETE_LOG="$MOLE_DELETE_LOG" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
unset MOLE_TEST_TRASH_DIR MOLE_TEST_NO_AUTH
export MOLE_DELETE_MODE=trash
export HOME="$SANDBOX/home"
export PATH="$SANDBOX/bin:$PATH"
victim="$SANDBOX/owned-agent.plist"
stage="$SANDBOX/stage-refused-agent"
identity=$(mole_deletion_identity "$victim")
digest=$(mole_file_sha256 "$victim")
_mole_privileged_path_has_mutable_ancestor() { return 1; }
_mole_create_privileged_trash_stage() {
    mkdir -p "$stage"
    printf '%s\n' "$stage"
}
_mole_trash_target_still_safe() {
    printf 'new owner\n' > "$victim"
    return 0
}
rc=0
mole_delete "$victim" true "$identity" "$digest" || rc=$?
[[ $rc -ne 0 && -f "$victim" && ! -e "$stage" ]] || exit 1
grep -q $'\townership-unverified\t' "$MOLE_DELETE_LOG"
EOF

    [ "$status" -eq 0 ] || {
        echo "$output"
        return 1
    }
    [[ "$output" == *"agent file changed or could not be inspected"* ]] || return 1
    [[ "$output" != *"Trash unavailable"* ]]
}

@test "mole_delete refuses symlinked invoking user Trash for sudo-required paths" {
    local victim="$SANDBOX/victim_sudo_symlink_trash"
    local fake_bin="$SANDBOX/bin"
    local fake_home="$SANDBOX/home"
    local redirected="$SANDBOX/redirected"
    local trace="$SANDBOX/trace.log"

    mkdir -p "$fake_bin" "$fake_home" "$redirected" "$victim"
    printf 'payload' > "$victim/data.txt"
    ln -s "$redirected" "$fake_home/.Trash"

    cat > "$fake_bin/sudo" <<'SH'
#!/bin/bash
printf 'sudo %s\n' "$*" >> "$MOLE_TEST_TRACE"
if [[ "${1:-}" == "-n" ]]; then
    shift
fi
"$@"
SH
    chmod +x "$fake_bin/sudo"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
unset MOLE_TEST_TRASH_DIR
unset MOLE_TEST_NO_AUTH
export MOLE_DELETE_MODE=trash
export PATH="$fake_bin:\$PATH"
export HOME="$fake_home"
export MOLE_TEST_TRACE="$trace"
_mole_privileged_path_has_mutable_ancestor() { return 1; }
mole_delete "$victim" true
EOF

    [ "$status" -ne 0 ]
    [[ -e "$victim" ]] || return 1
    [[ -z "$(ls -A "$redirected" 2> /dev/null || true)" ]] || return 1
    [[ "$(grep -c '^sudo -n /bin/mv ' "$trace" 2> /dev/null || true)" -eq 0 ]] || return 1

    local status_col
    status_col=$(awk -F'\t' 'END { print $4 }' "$MOLE_DELETE_LOG")
    [ "$status_col" = "trash-failed" ]
}

@test "mole_delete uses unique Trash name for sudo-required path conflicts" {
    local victim="$SANDBOX/conflict_app"
    local fake_bin="$SANDBOX/bin"
    local fake_home="$SANDBOX/home"
    local trace="$SANDBOX/trace.log"

    mkdir -p "$fake_bin" "$fake_home/.Trash" "$victim"
    printf 'payload' > "$victim/data.txt"
    mkdir -p "$fake_home/.Trash/$(basename "$victim")"

    cat > "$fake_bin/sudo" <<'SH'
#!/bin/bash
printf 'sudo %s\n' "$*" >> "$MOLE_TEST_TRACE"
if [[ "${1:-}" == "-n" ]]; then
    shift
fi
"$@"
SH
    chmod +x "$fake_bin/sudo"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
unset MOLE_TEST_TRASH_DIR
unset MOLE_TEST_NO_AUTH
export MOLE_DELETE_MODE=trash
export PATH="$fake_bin:\$PATH"
export HOME="$fake_home"
export MOLE_TEST_TRACE="$trace"
_mole_privileged_path_has_mutable_ancestor() { return 1; }
_mole_create_privileged_trash_stage() {
    local stage="$SANDBOX/stage-conflict-trash"
    mkdir -p "\$stage"
    printf '%s\n' "\$stage"
}
mole_delete "$victim" true
EOF

    [ "$status" -eq 0 ]
    [[ ! -e "$victim" ]] || return 1
    [[ -d "$fake_home/.Trash/$(basename "$victim")" ]] || return 1
    [[ -n "$(find "$fake_home/.Trash" -mindepth 1 -maxdepth 1 -name "$(basename "$victim").*" -print -quit)" ]] || return 1
    [[ "$(grep -c '^sudo -n /bin/mv ' "$trace" 2> /dev/null || true)" -eq 1 ]] || return 1

    local status_col
    status_col=$(awk -F'\t' 'END { print $4 }' "$MOLE_DELETE_LOG")
    [ "$status_col" = "ok" ]
}

@test "sudo Trash preserves staged payload without privileged rollback after handoff" {
    local victim="$SANDBOX/recovery_app"
    local fake_home="$SANDBOX/home"
    local stage="$SANDBOX/recovery-stage"
    local trace="$SANDBOX/recovery-sudo.log"

    mkdir -p "$fake_home" "$victim"
    printf 'payload' > "$victim/data.txt"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
unset MOLE_TEST_TRASH_DIR
unset MOLE_TEST_NO_AUTH
export MOLE_DELETE_MODE=trash
export HOME="$fake_home"
_mole_privileged_path_has_mutable_ancestor() { return 1; }
_mole_create_privileged_trash_stage() {
    command chmod 500 "$fake_home/.Trash"
    mkdir -p "$stage"
    printf '%s\n' "$stage"
}
sudo() {
    [[ "\${1:-}" == "-n" ]] && shift
    printf '%s\n' "\$*" >> "$trace"
    "\$@"
}
set +e
mole_delete "$victim" true
rc=\$?
set -e
printf 'RC=%s\n' "\$rc"
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"RC=1"* ]] || return 1
    [[ "$output" == *"item preserved for recovery"* ]] || return 1
    [[ ! -e "$victim" ]] || return 1
    [[ -f "$stage/item/data.txt" ]] || return 1
    [[ "$(grep -c "/bin/rm -rf $stage" "$trace" 2> /dev/null || true)" -eq 0 ]] || return 1
    [[ "$(grep -c "/bin/mv $stage/item $victim" "$trace" 2> /dev/null || true)" -eq 0 ]]
}

@test "privileged Trash staging never uses world-writable Library Caches" {
    run grep -nF '/Library/Caches/.mole-trash' "$PROJECT_ROOT/lib/core/file_ops.sh"
    [ "$status" -ne 0 ]

    run grep -nF 'stage_root="/Library/MoleTrashStaging"' "$PROJECT_ROOT/lib/core/file_ops.sh"
    [ "$status" -eq 0 ]
}

@test "Microsoft Word app path uses the direct Trash mover without trash or Finder" {
    local fake_home="$SANDBOX/home"
    local trace="$SANDBOX/direct-route.log"
    mkdir -p "$fake_home"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
unset MOLE_TEST_TRASH_DIR
unset MOLE_TEST_NO_AUTH
export HOME="$fake_home"
export MOLE_DELETE_MODE=trash
_mole_move_path_to_user_trash() {
    printf 'direct:%s:%s\n' "\$1" "\$2" >> "$trace"
    return 0
}
trash() {
    printf 'trash:%s\n' "\$*" >> "$trace"
    return 99
}
osascript() {
    printf 'osascript:%s\n' "\$*" >> "$trace"
    return 98
}
_mole_path_requires_direct_trash "/Applications/Microsoft Word.app"
! _mole_path_requires_direct_trash "/Applications/Utilities/Microsoft Word.app" || exit 1
! _mole_path_requires_direct_trash "/Applications/Microsoft Word.app/Contents" || exit 1
_mole_move_to_trash "/Applications/Microsoft Word.app" false
EOF

    [ "$status" -eq 0 ]
    grep -qF "direct:/Applications/Microsoft Word.app:false" "$trace"
    [[ "$(grep -c '^trash:' "$trace" 2> /dev/null || true)" -eq 0 ]] || return 1
    [[ "$(grep -c '^osascript:' "$trace" 2> /dev/null || true)" -eq 0 ]]
}

@test "mixed-case app suffix still uses the application Trash path" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
_mole_path_is_application_bundle "/Applications/Example.APP"
_mole_path_requires_direct_trash "/Applications/Example.App"
EOF

    [ "$status" -eq 0 ]
}

@test "application Trash falls back to Finder after a direct TCC denial" {
    local trace="$SANDBOX/app-finder-fallback.log"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
unset MOLE_TEST_TRASH_DIR
unset MOLE_TEST_NO_AUTH
export MOLE_DELETE_MODE=trash
_mole_move_path_to_user_trash() {
    printf 'direct:%s:%s\n' "\$1" "\$2" >> "$trace"
    return "\$MOLE_ERR_PRIVACY_DENIED"
}
_mole_move_app_to_trash_via_finder() {
    printf 'finder:%s\n' "\$1" >> "$trace"
    return 0
}
_mole_move_to_trash "/Applications/Developer.app" false
EOF

    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    [[ "$(grep -c '^direct:/Applications/Developer.app:false$' "$trace" 2> /dev/null || true)" -eq 1 ]] || return 1
    [[ "$(grep -c '^finder:/Applications/Developer.app$' "$trace" 2> /dev/null || true)" -eq 1 ]]
}

@test "Trash mode refuses sudo-required app below mutable Applications" {
    local victim="$SANDBOX/RootOwned.app"
    local trace="$SANDBOX/finder-app.log"
    mkdir -p "$victim"
    printf 'payload' > "$victim/data.txt"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
unset MOLE_TEST_TRASH_DIR
unset MOLE_TEST_NO_AUTH
export MOLE_DELETE_MODE=trash
_mole_privileged_path_has_mutable_ancestor() { return 0; }
_mole_move_path_to_user_trash() {
    printf 'DIRECT:%s:%s\n' "\$1" "\$2" >> "$trace"
}
osascript() {
    printf 'FINDER:%s\n' "\$*" >> "$trace"
}
set +e
mole_delete "$victim" true
rc=\$?
set -e
printf 'RC=%s\n' "\$rc"
[[ \$rc -eq \$MOLE_ERR_MUTABLE_PARENT ]] || exit 1
EOF

    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    [[ -f "$victim/data.txt" ]] || return 1
    [[ "$output" == *"RC=15"* ]] || return 1
    [[ "$(grep -c '^FINDER:' "$trace" 2> /dev/null || true)" -eq 0 ]] || return 1
    [[ "$(grep -c '^DIRECT:' "$trace" 2> /dev/null || true)" -eq 0 ]] || return 1
    [ "$(awk -F'\t' 'END { print $4 }' "$MOLE_DELETE_LOG")" = "mutable-parent" ]
}

@test "Trash mode preserves mutable-parent classification when the second path probe catches a race" {
    local victim="$SANDBOX/RacedRootOwned.app"
    local fake_home="$SANDBOX/race-home"
    mkdir -p "$victim" "$fake_home"
    printf 'payload' > "$victim/data.txt"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
unset MOLE_TEST_TRASH_DIR
unset MOLE_TEST_NO_AUTH
export HOME="$fake_home"
export MOLE_DELETE_MODE=trash
probe_round=0
_mole_privileged_path_has_mutable_ancestor() {
    probe_round=\$((probe_round + 1))
    [[ \$probe_round -ge 2 ]]
}
run_with_timeout() { printf '1\n'; }
set +e
mole_delete "$victim" true
rc=\$?
set -e
printf 'RC=%s\n' "\$rc"
[[ \$rc -eq \$MOLE_ERR_MUTABLE_PARENT ]] || exit 1
EOF

    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    [[ -f "$victim/data.txt" ]] || return 1
    [[ "$output" == *"RC=15"* ]] || return 1
    [[ "$output" != *"Use --permanent"* ]] || return 1
    [ "$(awk -F'\t' 'END { print $4 }' "$MOLE_DELETE_LOG")" = "mutable-parent" ]
}

@test "permanent delete refuses sudo-required app below mutable Applications" {
    local victim="$SANDBOX/RootOwnedPermanent.app"
    local trace="$SANDBOX/permanent-app.log"
    mkdir -p "$victim"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
unset MOLE_TEST_NO_AUTH
export MOLE_DELETE_MODE=permanent
_mole_privileged_path_has_mutable_ancestor() { return 0; }
safe_remove() { printf 'SAFE_REMOVE\n' >> "$trace"; return 0; }
safe_sudo_remove() { printf 'SAFE_SUDO_REMOVE\n' >> "$trace"; return 0; }
set +e
mole_delete "$victim" true
rc=\$?
set -e
printf 'RC=%s\n' "\$rc"
[[ \$rc -eq \$MOLE_ERR_MUTABLE_PARENT ]] || exit 1
EOF

    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    [[ -d "$victim" ]] || return 1
    [[ "$output" == *"RC=15"* ]] || return 1
    [[ ! -s "$trace" ]] || return 1
    [ "$(awk -F'\t' 'END { print $4 }' "$MOLE_DELETE_LOG")" = "mutable-parent" ]
}

@test "permanent delete preserves mutable-parent classification when the sink recheck catches a race" {
    local victim="$SANDBOX/RacedPermanent.app"
    local trace="$SANDBOX/permanent-race.log"
    mkdir -p "$victim"
    printf 'payload' > "$victim/data.txt"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
unset MOLE_TEST_NO_AUTH
export MOLE_DELETE_MODE=permanent
probe_round=0
_mole_privileged_path_has_mutable_ancestor() {
    probe_round=\$((probe_round + 1))
    [[ \$probe_round -ge 2 ]]
}
run_with_timeout() { printf '1\n'; }
safe_remove() { printf 'SAFE_REMOVE\n' >> "$trace"; return 0; }
safe_sudo_remove() { printf 'SAFE_SUDO_REMOVE\n' >> "$trace"; return 0; }
set +e
mole_delete "$victim" true
rc=\$?
set -e
printf 'RC=%s\n' "\$rc"
[[ \$rc -eq \$MOLE_ERR_MUTABLE_PARENT ]] || exit 1
EOF

    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    [[ -f "$victim/data.txt" ]] || return 1
    [[ "$output" == *"RC=15"* ]] || return 1
    [[ ! -s "$trace" ]] || return 1
    [ "$(awk -F'\t' 'END { print $4 }' "$MOLE_DELETE_LOG")" = "mutable-parent" ]
}

@test "permanent symlink delete preserves mutable-parent classification at the sink" {
    local target="$SANDBOX/target.app"
    local victim="$SANDBOX/RacedPermanentLink.app"
    local trace="$SANDBOX/permanent-link-race.log"
    mkdir -p "$target"
    ln -s "$target" "$victim"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
unset MOLE_TEST_NO_AUTH
export MOLE_DELETE_MODE=permanent
probe_round=0
_mole_privileged_path_has_mutable_ancestor() {
    probe_round=\$((probe_round + 1))
    [[ \$probe_round -ge 2 ]]
}
run_with_timeout() { printf '1\n'; }
safe_remove_symlink() { printf 'SAFE_REMOVE_SYMLINK\n' >> "$trace"; return 0; }
set +e
mole_delete "$victim" true
rc=\$?
set -e
printf 'RC=%s\n' "\$rc"
[[ \$rc -eq \$MOLE_ERR_MUTABLE_PARENT ]] || exit 1
EOF

    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    [[ -L "$victim" ]] || return 1
    [[ "$output" == *"RC=15"* ]] || return 1
    [[ ! -s "$trace" ]] || return 1
    [ "$(awk -F'\t' 'END { print $4 }' "$MOLE_DELETE_LOG")" = "mutable-parent" ]
}

@test "normal app data uses direct Trash with a unique name and mode 0700" {
    local fake_home="$SANDBOX/home"
    local victim="$fake_home/Library/Containers/com.microsoft.Word"
    local existing="$fake_home/.Trash/com.microsoft.Word"
    local trace="$SANDBOX/direct-user.log"
    mkdir -p "$victim" "$existing"
    printf 'document state' > "$victim/state.db"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
unset MOLE_TEST_TRASH_DIR
unset MOLE_TEST_NO_AUTH
export HOME="$fake_home"
export MOLE_DELETE_MODE=trash
export MOLE_UNINSTALL_MODE=1
trash() {
    printf 'trash:%s\n' "\$*" >> "$trace"
    return 99
}
osascript() {
    printf 'osascript:%s\n' "\$*" >> "$trace"
    return 98
}
mole_delete "$victim" false
EOF

    [ "$status" -eq 0 ]
    [[ ! -e "$victim" ]] || return 1
    [[ -d "$existing" ]] || return 1
    [[ -n "$(find "$fake_home/.Trash" -mindepth 1 -maxdepth 1 -name 'com.microsoft.Word.*' -print -quit)" ]] || return 1
    [ "$(stat -f '%Lp' "$fake_home/.Trash")" = "700" ]
    [[ "$(grep -c '^trash:' "$trace" 2> /dev/null || true)" -eq 0 ]] || return 1
    [[ "$(grep -c '^osascript:' "$trace" 2> /dev/null || true)" -eq 0 ]]
}

@test "normal direct Trash refuses a symlinked invoking user Trash" {
    local fake_home="$SANDBOX/home"
    local victim="$fake_home/Library/Application Scripts/com.microsoft.Word"
    local redirected="$SANDBOX/redirected"
    mkdir -p "$victim" "$redirected"
    ln -s "$redirected" "$fake_home/.Trash"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
unset MOLE_TEST_TRASH_DIR
unset MOLE_TEST_NO_AUTH
export HOME="$fake_home"
export MOLE_DELETE_MODE=trash
export MOLE_UNINSTALL_MODE=1
mole_delete "$victim" false
EOF

    [ "$status" -ne 0 ]
    [[ -d "$victim" ]] || return 1
    [[ -z "$(ls -A "$redirected" 2> /dev/null || true)" ]]
}

@test "direct Trash reports TCC denial and never falls back to permanent delete" {
    local fake_home="$SANDBOX/home"
    local victim="$fake_home/Library/Containers/com.microsoft.Word"
    local trace="$SANDBOX/privacy-denied.log"
    mkdir -p "$victim"
    printf 'document state' > "$victim/state.db"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
unset MOLE_TEST_TRASH_DIR
unset MOLE_TEST_NO_AUTH
export HOME="$fake_home"
export MOLE_DELETE_MODE=trash
export MOLE_UNINSTALL_MODE=1
mv() {
    printf 'mv: %s: Operation not permitted\n' "\$2" >&2
    return 1
}
trash() {
    printf 'trash\n' >> "$trace"
    return 99
}
osascript() {
    printf 'osascript\n' >> "$trace"
    return 98
}
safe_remove() {
    printf 'safe_remove\n' >> "$trace"
    return 97
}
set +e
mole_delete "$victim" false
rc=\$?
set -e
printf 'RC=%s\n' "\$rc"
[[ \$rc -eq \$MOLE_ERR_PRIVACY_DENIED ]] || exit 1
EOF

    [ "$status" -eq 0 ]
    [[ -d "$victim" ]] || return 1
    [[ "$output" == *"Try moving the item to Trash in Finder. Run with --debug for details"* ]] || return 1
    [[ "$output" != *"Full Disk Access"* ]] || return 1
    [[ "$output" != *"Touch ID"* ]] || return 1
    [[ "$output" == *"RC=14"* ]] || return 1
    [[ ! -s "$trace" ]] || return 1
    [ "$(awk -F'\t' 'END { print $4 }' "$MOLE_DELETE_LOG")" = "privacy-denied" ]
}

@test "direct Trash recognizes lowercase permission denied" {
    local fake_home="$SANDBOX/home"
    local victim="$fake_home/Library/Group Containers/UBF8T346G9.Office"
    mkdir -p "$victim"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
unset MOLE_TEST_TRASH_DIR
unset MOLE_TEST_NO_AUTH
export HOME="$fake_home"
mv() {
    printf 'mv: permission denied\n' >&2
    return 1
}
set +e
_mole_move_path_to_user_trash "$victim" false
rc=\$?
set -e
printf 'RC=%s\n' "\$rc"
[[ \$rc -eq \$MOLE_ERR_PRIVACY_DENIED ]] || exit 1
EOF

    [ "$status" -eq 0 ]
    [[ -d "$victim" ]] || return 1
    [[ "$output" == *"RC=14"* ]]
}

@test "direct Trash generic failure stays closed" {
    local fake_home="$SANDBOX/home"
    local victim="$fake_home/Library/Application Scripts/com.microsoft.Word"
    local trace="$SANDBOX/generic-failure.log"
    mkdir -p "$victim"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
unset MOLE_TEST_TRASH_DIR
unset MOLE_TEST_NO_AUTH
export HOME="$fake_home"
export MOLE_DELETE_MODE=trash
export MOLE_UNINSTALL_MODE=1
mv() {
    printf 'mv: input/output error\n' >&2
    return 1
}
trash() {
    printf 'trash\n' >> "$trace"
    return 99
}
osascript() {
    printf 'osascript\n' >> "$trace"
    return 98
}
safe_remove() {
    printf 'safe_remove\n' >> "$trace"
    return 97
}
set +e
mole_delete "$victim" false
rc=\$?
set -e
[[ \$rc -eq 1 ]] || exit 1
EOF

    [ "$status" -eq 0 ]
    [[ -d "$victim" ]] || return 1
    [[ ! -s "$trace" ]] || return 1
    [[ "$output" == *"refusing permanent delete"* ]]
}

@test "privacy denial diagnosis offers Finder and debug without guessing a permission pane" {
    run /bin/bash --noprofile --norc <<EOF
$(prelude)
diagnose_removal_failure "\$MOLE_ERR_PRIVACY_DENIED" "Microsoft Word"
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"macOS denied Trash access"* ]] || return 1
    [[ "$output" == *"Try moving the item to Trash in Finder. Run with --debug for details"* ]] || return 1
    [[ "$output" != *"Full Disk Access"* ]] || return 1
    [[ "$output" != *"touchid"* ]] || return 1
    [[ "$output" != *"Touch ID"* ]]
}

@test "mutable-parent diagnosis recommends manual Trash without promising container cleanup" {
    run /bin/bash --noprofile --norc <<EOF
$(prelude)
diagnose_removal_failure "\$MOLE_ERR_MUTABLE_PARENT" "Microsoft Word"
EOF

    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    [[ "$output" == *"cannot safely use elevated deletion"* ]] || return 1
    [[ "$output" == *"Move the app to Trash in Finder"* ]] || return 1
    [[ "$output" == *"protected containers and app data untouched"* ]] || return 1
    [[ "$output" != *"mo clean"* ]] || return 1
}

@test "unrelated removal diagnostics do not probe Touch ID" {
    run /bin/bash --noprofile --norc <<EOF
$(prelude)
touchid_checks=0
check_touchid_support() {
    touchid_checks=\$((touchid_checks + 1))
    printf 'detector noise\n'
    return 0
}
diagnose_removal_failure "\$MOLE_ERR_SIP_PROTECTED" "Microsoft Word"
diagnose_removal_failure "\$MOLE_ERR_READONLY_FS" "Microsoft Word"
diagnose_removal_failure "\$MOLE_ERR_PROTECTED_PATH" "Microsoft Word"
diagnose_removal_failure "\$MOLE_ERR_PRIVACY_DENIED" "Microsoft Word"
printf 'checks=%s\n' "\$touchid_checks"
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"checks=0"* ]] || return 1
    [[ "$output" != *"detector noise"* ]]
}

@test "removal diagnosis uses the shared Touch ID detector" {
    run /bin/bash --noprofile --norc <<EOF
$(prelude)
touchid_checks=0
check_touchid_support() {
    touchid_checks=\$((touchid_checks + 1))
    printf 'detector noise\n'
    return 0
}
diagnose_removal_failure "\$MOLE_ERR_AUTH_FAILED" "Microsoft Word"
diagnose_removal_failure "1" "Microsoft Word"
printf 'checks=%s\n' "\$touchid_checks"
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"authentication failed|Check your credentials or restart Terminal"* ]] || return 1
    [[ "$output" == *"permission denied|Try running again or check file ownership"* ]] || return 1
    [[ "$output" == *"checks=2"* ]] || return 1
    [[ "$output" != *"detector noise"* ]] || return 1
    [[ "$output" != *"mole touchid"* ]]
}

@test "common library wires the production Touch ID detector into diagnosis" {
    run /bin/bash --noprofile --norc <<EOF
$(prelude)
[[ "\$(type -t check_touchid_support)" == "function" ]] || exit 1
if check_touchid_support; then
    expected="authentication failed|Check your credentials or restart Terminal"
else
    expected="authentication failed|Try 'mole touchid' to enable fingerprint auth"
fi
actual=\$(diagnose_removal_failure "\$MOLE_ERR_AUTH_FAILED" "Microsoft Word")
[[ "\$actual" == "\$expected" ]] || exit 1
printf 'production-detector-wired\n'
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"production-detector-wired"* ]]
}

@test "removal diagnosis retains Touch ID setup guidance when unavailable" {
    run /bin/bash --noprofile --norc <<EOF
$(prelude)
check_touchid_support() {
    return 1
}
diagnose_removal_failure "\$MOLE_ERR_AUTH_FAILED" "Microsoft Word"
diagnose_removal_failure "1" "Microsoft Word"
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"authentication failed|Try 'mole touchid' to enable fingerprint auth"* ]] || return 1
    [[ "$output" == *"permission denied|Try 'mole touchid' or check with 'ls -l'"* ]]
}

@test "removal diagnosis ignores a same-named executable when the detector is missing" {
    local fake_bin="$SANDBOX/bin"
    local trace="$SANDBOX/external-detector.log"
    mkdir -p "$fake_bin"
    cat > "$fake_bin/check_touchid_support" <<'SH'
#!/bin/bash
printf 'called\n' >> "$MOLE_TEST_TRACE"
exit 0
SH
    chmod +x "$fake_bin/check_touchid_support"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
unset -f check_touchid_support
export MOLE_TEST_TRACE="$trace"
export PATH="$fake_bin:\$PATH"
diagnose_removal_failure "\$MOLE_ERR_AUTH_FAILED" "Microsoft Word"
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"authentication failed|Try 'mole touchid' to enable fingerprint auth"* ]] || return 1
    [[ ! -e "$trace" ]]
}

@test "mole_delete writes a tab-separated log line per call" {
    local victim="$SANDBOX/logged"
    : > "$victim"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
mole_delete "$victim"
EOF

    [ "$status" -eq 0 ]
    [[ -s "$MOLE_DELETE_LOG" ]] || return 1

    # Expect 5 tab-separated fields: timestamp, mode, size_kb, status, path.
    local fields
    fields=$(awk -F'\t' 'END { print NF }' "$MOLE_DELETE_LOG")
    [ "$fields" -eq 5 ]

    # Status column must be "ok" for a successful permanent delete.
    local status_col
    status_col=$(awk -F'\t' 'END { print $4 }' "$MOLE_DELETE_LOG")
    [ "$status_col" = "ok" ]
}

@test "mole_delete rejects symlinks to protected system paths" {
    local victim="$SANDBOX/system-link"
    ln -s "/System" "$victim"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
mole_delete "$victim"
EOF

    [ "$status" -eq 1 ]
    [[ -L "$victim" ]] || return 1

    local status_col
    status_col=$(awk -F'\t' 'END { print $4 }' "$MOLE_DELETE_LOG")
    [ "$status_col" = "rejected" ]
}

@test "mole_delete dry-run does not touch the filesystem but still logs" {
    local victim="$SANDBOX/dry"
    : > "$victim"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
export MOLE_DRY_RUN=1
mole_delete "$victim"
EOF

    [ "$status" -eq 0 ]
    [[ -e "$victim" ]] || return 1

    local status_col
    status_col=$(awk -F'\t' 'END { print $4 }' "$MOLE_DELETE_LOG")
    [ "$status_col" = "dry-run" ]
}

@test "mole_delete records a forensic log entry for rejected paths" {
    run /bin/bash --noprofile --norc <<EOF
$(prelude)
mole_delete "/tmp/../etc/hosts"
EOF

    [ "$status" -ne 0 ]
    # Rejection IS logged (security-relevant), with status="rejected" and size=0.
    # Audit trails need to distinguish refused-by-policy from never-attempted.
    [[ -s "$MOLE_DELETE_LOG" ]] || return 1
    local status_col size_col
    status_col=$(awk -F'\t' 'END { print $4 }' "$MOLE_DELETE_LOG")
    size_col=$(awk -F'\t' 'END { print $3 }' "$MOLE_DELETE_LOG")
    [ "$status_col" = "rejected" ]
    [ "$size_col" = "0" ]
}

@test "mole_delete is a no-op on a non-existent path" {
    run /bin/bash --noprofile --norc <<EOF
$(prelude)
mole_delete "$SANDBOX/does-not-exist"
EOF

    [ "$status" -eq 0 ]
    [[ ! -s "$MOLE_DELETE_LOG" ]]
}

@test "mole_delete rejects unknown delete mode without touching target" {
    local victim="$SANDBOX/invalid_mode_target"
    : > "$victim"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
export MOLE_DELETE_MODE=surprise
mole_delete "$victim"
EOF

    [ "$status" -ne 0 ]
    [[ -e "$victim" ]] || return 1

    local mode_col status_col
    mode_col=$(awk -F'\t' 'END { print $2 }' "$MOLE_DELETE_LOG")
    status_col=$(awk -F'\t' 'END { print $4 }' "$MOLE_DELETE_LOG")
    [ "$mode_col" = "surprise" ]
    [ "$status_col" = "invalid-mode" ]
    [[ "$output" == *'expected "permanent" or "trash"'* ]]
}

@test "mole_delete warns once for repeated invalid delete mode" {
    local first="$SANDBOX/invalid_mode_first"
    local second="$SANDBOX/invalid_mode_second"
    : > "$first"
    : > "$second"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
export MOLE_DELETE_MODE=surprise
set +e
mole_delete "$first"
first_rc=\$?
mole_delete "$second"
second_rc=\$?
set -e
[[ \$first_rc -ne 0 && \$second_rc -ne 0 ]] || exit 1
EOF

    [ "$status" -eq 0 ]
    [[ -e "$first" ]] || return 1
    [[ -e "$second" ]] || return 1
    [[ "$(grep -c 'invalid MOLE_DELETE_MODE' <<< "$output")" -eq 1 ]]
}

@test "mole_delete trash failure leaves target in place" {
    local victim="$SANDBOX/fallback_target"
    : > "$victim"

    # Pointing MOLE_TEST_TRASH_DIR at a non-writable parent forces the stub
    # trash move to fail, exercising the fallback path.
    local blocked="$SANDBOX/blocked/Trash"
    mkdir -p "$(dirname "$blocked")"
    chmod 0555 "$(dirname "$blocked")"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
export MOLE_DELETE_MODE=trash
export MOLE_TEST_TRASH_DIR="$blocked"
mole_delete "$victim"
EOF

    chmod 0755 "$(dirname "$blocked")"

    [ "$status" -ne 0 ]
    [[ -e "$victim" ]] || return 1

    local status_col
    status_col=$(awk -F'\t' 'END { print $4 }' "$MOLE_DELETE_LOG")
    [ "$status_col" = "trash-failed" ]
    [[ "$output" == *"refusing permanent delete"* ]]
}

@test "mole_delete warns once for repeated Trash failures" {
    local first="$SANDBOX/trash_fail_first"
    local second="$SANDBOX/trash_fail_second"
    : > "$first"
    : > "$second"

    local blocked="$SANDBOX/blocked/Trash"
    mkdir -p "$(dirname "$blocked")"
    chmod 0555 "$(dirname "$blocked")"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
export MOLE_DELETE_MODE=trash
export MOLE_TEST_TRASH_DIR="$blocked"
set +e
mole_delete "$first"
first_rc=\$?
mole_delete "$second"
second_rc=\$?
set -e
[[ \$first_rc -ne 0 && \$second_rc -ne 0 ]] || exit 1
EOF

    chmod 0755 "$(dirname "$blocked")"

    [ "$status" -eq 0 ]
    [[ -e "$first" ]] || return 1
    [[ -e "$second" ]] || return 1
    [[ "$(grep -c "Trash unavailable" <<< "$output")" -eq 1 ]]
}

@test "mole_delete records 'unknown' (not 0) when size measurement fails" {
    # Override get_path_size_kb to simulate a measurement failure (non-numeric
    # output, non-zero exit). The actual delete still goes through safe_remove
    # so the file is removed; only the log size column should differ.
    local victim="$SANDBOX/measureless"
    : > "$victim"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
get_path_size_kb() { echo "ERR"; return 1; }
mole_delete "$victim"
EOF

    [ "$status" -eq 0 ]
    [[ ! -e "$victim" ]] || return 1
    local size_col
    size_col=$(awk -F'\t' 'END { print $3 }' "$MOLE_DELETE_LOG")
    [ "$size_col" = "unknown" ]
}

@test "mole_delete stops before Trash or permanent removal when sizing is interrupted" {
    local trash_victim="$SANDBOX/interrupted-trash-size"
    local sudo_victim="$SANDBOX/interrupted-sudo-size"
    mkdir -p "$trash_victim" "$sudo_victim"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
get_path_size_kb() { return 130; }
_mole_move_to_trash() {
    printf 'UNEXPECTED_TRASH:%s\n' "\$1"
    return 99
}
safe_remove() {
    printf 'UNEXPECTED_REMOVE:%s\n' "\$1"
    return 99
}

export MOLE_DELETE_MODE=trash
trash_rc=0
mole_delete "$trash_victim" || trash_rc=\$?
printf 'TRASH_RC=%s\n' "\$trash_rc"

unset MOLE_TEST_NO_AUTH
export MOLE_DELETE_MODE=permanent
_mole_privileged_path_has_mutable_ancestor() { return 1; }
run_with_timeout() { return 130; }
safe_sudo_remove() {
    printf 'UNEXPECTED_SUDO_REMOVE:%s\n' "\$1"
    return 99
}
sudo_rc=0
mole_delete "$sudo_victim" true || sudo_rc=\$?
printf 'SUDO_RC=%s\n' "\$sudo_rc"
EOF

    [ "$status" -eq 0 ] || return 1
    [[ "$output" == *"TRASH_RC=130"* ]] || return 1
    [[ "$output" == *"SUDO_RC=130"* ]] || return 1
    [[ "$output" != *"UNEXPECTED_"* ]] || return 1
    [[ -e "$trash_victim" ]] || return 1
    [[ -e "$sudo_victim" ]]
}

@test "mole_delete preserves an interrupted Trash action in its return code and forensic log" {
    local victim="$SANDBOX/interrupted-trash-action"
    mkdir -p "$victim"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
export MOLE_DELETE_MODE=trash
_mole_move_to_trash() { return 130; }
safe_remove() {
    printf 'UNEXPECTED_REMOVE:%s\n' "\$1"
    return 99
}
rc=0
mole_delete "$victim" || rc=\$?
printf 'RC=%s\n' "\$rc"
EOF

    [ "$status" -eq 0 ] || return 1
    [[ "$output" == *"RC=130"* ]] || return 1
    [[ "$output" != *"UNEXPECTED_REMOVE"* ]] || return 1
    [[ -d "$victim" ]] || return 1
    [ "$(awk -F'\t' 'END { print $4 }' "$MOLE_DELETE_LOG")" = "interrupted" ]
}

@test "safe_remove refuses a replacement reached through a swapped parent" {
    local parent="$SANDBOX/bound-parent"
    local victim="$parent/victim"
    mkdir -p "$victim"
    printf 'original\n' > "$victim/data"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
_mole_snapshot_path_identity "$victim"
expected_parent="\$_MOLE_PATH_SNAPSHOT_PARENT"
expected_parent_id="\$_MOLE_PATH_SNAPSHOT_PARENT_ID"
expected_target_id="\$_MOLE_PATH_SNAPSHOT_TARGET_ID"

mv "$parent" "$parent.original"
mkdir -p "$victim"
printf 'replacement\n' > "$victim/data"

rc=0
safe_remove "$victim" true 1 "" \
    "\$expected_parent" "\$expected_parent_id" "\$expected_target_id" || rc=\$?
[[ \$rc -ne 0 ]] || exit 1
[[ -f "$victim/data" && -f "$parent.original/victim/data" ]]
EOF

    [ "$status" -eq 0 ] || {
        echo "$output"
        return 1
    }
}

@test "safe_remove records a clean interruption and blocks later deletion sinks" {
    local first="$SANDBOX/interrupted-clean-delete"
    local second="$SANDBOX/later-clean-delete"
    mkdir -p "$first" "$second"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
export MOLE_CURRENT_COMMAND=clean
export MOLE_CLEAN_CANCEL_STATUS=0
rm() { return 130; }
rc=0
safe_remove "$first" true 1 || rc=\$?
[[ \$rc -eq 130 ]] || exit 1
[[ \$MOLE_CLEAN_CANCEL_STATUS -eq 130 ]] || exit 1

rm() {
    printf 'UNEXPECTED_RM:%s\n' "\$1"
    /bin/rm "\$@"
}
rc=0
safe_remove "$second" true 1 || rc=\$?
[[ \$rc -eq 130 ]] || exit 1
[[ -d "$first" && -d "$second" ]]
EOF

    [ "$status" -eq 0 ] || {
        echo "$output"
        return 1
    }
    [[ "$output" != *"UNEXPECTED_RM"* ]]
}

@test "path identity rejects incomplete metadata without retaining a previous binding" {
    run env PROJECT_ROOT="$PROJECT_ROOT" SANDBOX="$SANDBOX" /bin/bash <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
mkdir -p "$SANDBOX/artifact with spaces"
_mole_snapshot_path_identity "$SANDBOX/artifact with spaces"
[[ -n "$_MOLE_PATH_SNAPSHOT_TARGET_ID" ]] || exit 1
function /usr/bin/stat { printf '1:2\n'; }
if _mole_snapshot_path_identity "$SANDBOX/artifact with spaces"; then
    exit 1
fi
[[ -z "$_MOLE_PATH_SNAPSHOT_PARENT" && -z "$_MOLE_PATH_SNAPSHOT_PARENT_ID" && -z "$_MOLE_PATH_SNAPSHOT_TARGET_ID" ]] || exit 1
EOF
    [ "$status" -eq 0 ]
}

@test "mole_delete never binds a replacement installed during identity snapshot" {
    local victim="$SANDBOX/snapshot-race.app"
    mkdir -p "$victim"
    printf 'original\n' > "$victim/data"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
export MOLE_DELETE_MODE=permanent
expected_identity=\$("\$STAT_BSD" -f%d:%i:%m "$victim")
eval "\$(declare -f _mole_snapshot_path_identity | sed '1s/_mole_snapshot_path_identity/_real_mole_snapshot_path_identity/')"
_mole_snapshot_path_identity() {
    _real_mole_snapshot_path_identity "\$1" || return \$?
    mv "\$1" "\$1.original"
    mkdir -p "\$1"
    printf 'replacement\n' > "\$1/data"
}
safe_remove() {
    printf 'UNEXPECTED_REMOVE:%s\n' "\$1"
    return 0
}

rc=0
mole_delete "$victim" false "\$expected_identity" || rc=\$?
[[ \$rc -ne 0 ]] || exit 1
[[ -f "$victim/data" && -f "$victim.original/data" ]]
EOF

    [ "$status" -eq 0 ] || {
        echo "$output"
        return 1
    }
    [[ "$output" != *"UNEXPECTED_REMOVE"* ]]
}

@test "Finder fallback refuses an app replaced after direct Trash denial" {
    local victim="$SANDBOX/Raced.app"
    local trace="$SANDBOX/raced-finder.log"
    mkdir -p "$victim"
    printf 'original\n' > "$victim/data"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
unset MOLE_TEST_TRASH_DIR
unset MOLE_TEST_NO_AUTH
export MOLE_DELETE_MODE=trash
expected_identity=\$("\$STAT_BSD" -f%d:%i:%m "$victim")
_mole_path_requires_direct_trash() { return 0; }
_mole_path_is_application_bundle() { return 0; }
_mole_move_path_to_user_trash() {
    mv "\$1" "\$1.original"
    mkdir -p "\$1"
    printf 'replacement\n' > "\$1/data"
    return "\$MOLE_ERR_PRIVACY_DENIED"
}
osascript() {
    printf 'UNEXPECTED_FINDER:%s\n' "\$*" >> "$trace"
    return 0
}

rc=0
mole_delete "$victim" false "\$expected_identity" || rc=\$?
[[ \$rc -ne 0 ]] || exit 1
[[ -f "$victim/data" && -f "$victim.original/data" ]]
EOF

    [ "$status" -eq 0 ] || {
        echo "$output"
        return 1
    }
    [[ ! -e "$trace" ]]
}

@test "mole_delete dry-run propagates an interrupted preview registration" {
    local victim="$SANDBOX/interrupted-preview"
    mkdir -p "$victim"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
export MOLE_DRY_RUN=1
_record_file_ops_dry_run_target() { return 130; }
safe_remove() {
    printf 'UNEXPECTED_REMOVE:%s\n' "\$1"
    return 99
}
rc=0
mole_delete "$victim" || rc=\$?
printf 'RC=%s\n' "\$rc"
EOF

    [ "$status" -eq 0 ] || return 1
    [[ "$output" == *"RC=130"* ]] || return 1
    [[ "$output" != *"UNEXPECTED_REMOVE"* ]] || return 1
    [[ -d "$victim" ]] || return 1
    [ "$(awk -F'\t' 'END { print $4 }' "$MOLE_DELETE_LOG")" = "interrupted" ]
}

@test "mole_delete warns once per session when audit log is unwritable" {
    local victim="$SANDBOX/log_blocked"
    : > "$victim"
    local broken_log_dir="$SANDBOX/no_write/logs"
    mkdir -p "$(dirname "$broken_log_dir")"
    chmod 0555 "$(dirname "$broken_log_dir")"

    run /bin/bash --noprofile --norc <<EOF
set -euo pipefail
export MOLE_DELETE_LOG="$broken_log_dir/deletions.log"
export MOLE_TEST_TRASH_DIR="$MOLE_TEST_TRASH_DIR"
export MOLE_TEST_NO_AUTH=1
source "$PROJECT_ROOT/lib/core/common.sh"
mole_delete "$victim"
# Second call in the same shell must NOT print again.
: > "$SANDBOX/second_victim"
mole_delete "$SANDBOX/second_victim"
EOF

    chmod 0755 "$(dirname "$broken_log_dir")"

    [ "$status" -eq 0 ]
    # Warning visible exactly once.
    local warn_count
    warn_count=$(printf '%s\n' "$output" | grep -c "deletions audit log unavailable" || true)
    [ "$warn_count" = "1" ]
}

@test "get_path_size_kb bounds a hung du instead of wedging the sizing worker" {
    # Regression: the primary sizing du (file_ops.sh get_path_size_kb) ran
    # WITHOUT run_with_timeout while every sibling call site was bounded, so
    # one stalled SMB/FUSE mount wedged a parallel scan worker forever. The
    # stub du sleeps far past the 1s override; a bounded helper returns the
    # timeout status quickly, while an unbounded one trips the bats timeout.
    local stub_dir="$SANDBOX/stub-bin"
    mkdir -p "$stub_dir"
    cat > "$stub_dir/du" <<'STUB'
#!/bin/bash
sleep 30
echo "999999 /"
STUB
    chmod +x "$stub_dir/du"

    local victim_dir="$SANDBOX/big-dir"
    mkdir -p "$victim_dir"

    local started elapsed
    started=$SECONDS
    run /bin/bash --noprofile --norc <<EOF
set -euo pipefail
export PATH="$stub_dir:\$PATH"
export MOLE_TIMEOUT_DISK_VERIFY_SEC=1
export MOLE_TEST_NO_AUTH=1
source "$PROJECT_ROOT/lib/core/common.sh"
get_path_size_kb "$victim_dir"
EOF
    elapsed=$((SECONDS - started))

    [ "$status" -eq 124 ]
    [ -z "$output" ] || return 1
    # Generous ceiling: 1s timeout + escalation grace, never 30s.
    [ "$elapsed" -lt 10 ] || return 1
}

@test "safe_sudo_remove accepts a precomputed size without another du probe" {
    local victim="$SANDBOX/precomputed-sudo"
    local fake_bin="$SANDBOX/precomputed-bin"
    local trace="$SANDBOX/precomputed-sudo.log"
    mkdir -p "$victim" "$fake_bin"
    printf 'payload' > "$victim/data.txt"

    cat > "$fake_bin/sudo" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "$MOLE_TEST_TRACE"
if [[ "${1:-}" == "-n" ]]; then
    shift
fi
"$@"
SH
    chmod +x "$fake_bin/sudo"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
unset MOLE_TEST_NO_AUTH MOLE_TEST_MODE
export PATH="$fake_bin:\$PATH"
export MOLE_TEST_TRACE="$trace"
_mole_privileged_path_has_mutable_ancestor() { return 1; }
safe_sudo_remove "$victim" 7
EOF

    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    [[ ! -e "$victim" ]] || return 1
    [[ "$(grep -c -- 'rm -rf' "$trace" 2> /dev/null || true)" -eq 1 ]] || return 1
    [[ "$(grep -c -- 'du -skP' "$trace" 2> /dev/null || true)" -eq 0 ]]
}

# The stage-root preparation is the part with a concurrency contract, and the
# Trash tests above mock the whole stage creator, so it needs its own coverage:
# two Mole processes can both observe a missing root, and a plain mkdir would
# make the loser abort a Trash move that was perfectly safe.
@test "privileged Trash stage root tolerates a concurrent creator" {
    local stage_root="$SANDBOX/stage-root"
    local trace="$SANDBOX/root-prep.log"
    local fake_bin="$SANDBOX/bin"

    mkdir -p "$fake_bin"
    # `mkdir` without -p loses the race: another process created the root between
    # this process's check and its own mkdir, which is the EEXIST the fix
    # absorbs. chown/chmod cannot really run unprivileged, so they report
    # success; reaching them at all is the evidence that mkdir did not abort.
    cat > "$fake_bin/sudo" <<'SH'
#!/bin/bash
printf 'sudo %s\n' "$*" >> "$MOLE_TEST_TRACE"
if [[ "${1:-}" == "-n" ]]; then
    shift
fi
case "$1" in
    */mkdir)
        shift
        if [[ "${1:-}" == "-p" ]]; then
            shift
            mkdir -p "$@"
            exit $?
        fi
        mkdir "$@" 2> /dev/null
        exit $?
        ;;
    */chown | */chmod) exit 0 ;;
esac
"$@"
SH
    chmod +x "$fake_bin/sudo"
    # The concurrent winner already created it.
    mkdir -p "$stage_root"
    : > "$trace"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
export PATH="$fake_bin:\$PATH"
export MOLE_TEST_TRACE="$trace"
_mole_prepare_privileged_trash_stage_root "$stage_root"
EOF

    # mkdir -p absorbed the existing root and the flow continued into the
    # ownership steps. A plain mkdir returns EEXIST and never reaches them.
    [[ "$(grep -c '^sudo -n /bin/mkdir -p ' "$trace" 2> /dev/null || true)" -eq 1 ]] || return 1
    [[ "$(grep -c '^sudo -n /usr/sbin/chown 0:0 ' "$trace" 2> /dev/null || true)" -eq 1 ]] || return 1
    [[ "$(grep -c '^sudo -n /bin/chmod 711 ' "$trace" 2> /dev/null || true)" -eq 1 ]] || return 1
    # The sandbox root is owned by the test user, so the verification gate must
    # still refuse it: tolerating EEXIST must not weaken the ownership check.
    [ "$status" -ne 0 ] || return 1
    [[ -d "$stage_root" ]]
}

@test "privileged Trash stage root refuses a symlinked root" {
    local real_dir="$SANDBOX/elsewhere"
    local stage_root="$SANDBOX/stage-root-link"
    local trace="$SANDBOX/root-link.log"

    mkdir -p "$real_dir"
    ln -s "$real_dir" "$stage_root"
    : > "$trace"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
export MOLE_TEST_TRACE="$trace"
sudo() { printf 'sudo %s\n' "\$*" >> "$trace"; return 0; }
_mole_prepare_privileged_trash_stage_root "$stage_root"
EOF

    [ "$status" -ne 0 ] || return 1
    # Nothing privileged may run against a symlinked root.
    [[ ! -s "$trace" ]]
}


@test "Finder automation denial names the permission and records the actual error (#1644)" {
    run_finder_result_fixture 1
    [[ "$output" == *"Privacy & Security > Automation"* ]] || return 1
    [[ "$output" == *"RC=1"* ]] || return 1
    [[ -d "$SANDBOX/FinderFixture.app" ]] || return 1
    local diagnostic
    diagnostic=$(cat "$SANDBOX/finder-debug.log")
    [[ "$diagnostic" == *"(exit 1)"* ]] || return 1
    [[ "$diagnostic" == *"Finder fixture diagnostic (-1743)"* ]] || return 1
    [[ "$diagnostic" != *"FINDER_STDOUT_MUST_STAY_HIDDEN"* ]]
}

@test "Finder success with a surviving app is diagnosed as an incomplete move" {
    run_finder_result_fixture 0
    [[ "$output" == "RC=1" ]] || return 1
    [[ -d "$SANDBOX/FinderFixture.app" ]] || return 1
    [[ "$(cat "$SANDBOX/finder-debug.log")" == *"Finder returned success but the application remains:"* ]]
}

@test "Finder timeout and signal preserve status and failure diagnostics" {
    local rc diagnostic
    for rc in 124 130; do
        : > "$SANDBOX/finder-debug.log"
        run_finder_result_fixture "$rc"
        [[ "$output" == "RC=$rc" ]] || return 1
        [[ -d "$SANDBOX/FinderFixture.app" ]] || return 1
        diagnostic=$(cat "$SANDBOX/finder-debug.log")
        [[ "$diagnostic" == *"(exit $rc)"* ]] || return 1
        [[ "$diagnostic" == *"Finder fixture diagnostic (-1743)"* ]] || return 1
    done
}

@test "Finder successful mock move remains quiet and verifies the survivor" {
    run_finder_result_fixture 0 1
    [[ "$output" == "RC=0" ]] || return 1
    [[ ! -e "$SANDBOX/FinderFixture.app" && -d "$SANDBOX/MovedFixture.app" ]] || return 1
    [[ "$(cat "$SANDBOX/finder-debug.log")" == *"Finder moved application to Trash:"* ]]
}

@test "Trash no-auth guard prevents both direct and Finder execution" {
    run /bin/bash --noprofile --norc <<EOF
$(prelude)
unset MOLE_TEST_TRASH_DIR
_mole_move_path_to_user_trash() { echo UNEXPECTED_DIRECT; return 99; }
_mole_move_app_to_trash_via_finder() { echo UNEXPECTED_FINDER; return 99; }
rc=0
_mole_move_to_trash /Applications/Fixture.app false || rc=\$?
printf 'RC=%s\n' "\$rc"
EOF
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    [[ "$output" == "RC=1" ]]
}


@test "mole_delete preserves validation cancellation status" {
    local probe_rc failures=0
    for probe_rc in 1 124 130; do
        run env PROJECT_ROOT="$PROJECT_ROOT" PROBE_RC="$probe_rc" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
export MOLE_CURRENT_COMMAND=uninstall
victim="$SANDBOX/validation-victim"
mkdir -p "$victim"
validate_path_for_deletion() { return "$PROBE_RC"; }
get_path_size_kb() { echo UNEXPECTED_SIZE_PROBE; return 97; }
rc=0
mole_delete "$victim" false || rc=$?
[[ $rc -eq $PROBE_RC && -d "$victim" ]] || exit 1
case "$PROBE_RC" in
    1) reason=rejected ;;
    124) reason=timed-out ;;
    130) reason=interrupted ;;
esac
grep -q "$(printf '\t%s\t' "$reason")" "$MOLE_DELETE_LOG" || exit 1
EOF
        [ "$status" -eq 0 ] || { echo "probe=$probe_rc: $output"; failures=$((failures + 1)); }
        [[ "$output" != *UNEXPECTED_SIZE_PROBE* ]] || return 1
    done
    [ "$failures" -eq 0 ]
}

@test "Trash batch preserves cancellation and completed paths at both sinks" {
    local probe_rc sink failures=0
    for sink in direct test-trash; do
        for probe_rc in 1 124 130; do
            run env PROJECT_ROOT="$PROJECT_ROOT" PROBE_RC="$probe_rc" SINK="$sink" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
export MOLE_CURRENT_COMMAND=uninstall
fixture="$SANDBOX/batch-$SINK-$PROBE_RC"
mkdir -p "$fixture/first" "$fixture/second" "$fixture/third"
first="$fixture/first"
second="$fixture/second"
third="$fixture/third"
if [[ "$SINK" == direct ]]; then
    unset MOLE_TEST_TRASH_DIR
    MOLE_TEST_NO_AUTH=0
    _mole_move_path_to_user_trash() {
        printf '%s\n' "$1" >> "$fixture/trace"
        [[ "$1" == "$second" ]] && return "$PROBE_RC"
        rmdir "$1"
    }
else
    MOLE_TEST_TRASH_DIR="$fixture/Trash"
    _mole_trash_target_still_safe() {
        printf '%s\n' "$1" >> "$fixture/trace"
        [[ "$1" == "$second" ]] && return "$PROBE_RC"
        return 0
    }
fi
rc=0
_mole_move_to_trash_batch "$first" "$second" "$third" || rc=$?
[[ $rc -eq $PROBE_RC ]] || exit 1
[[ ! -e "$first" && -d "$second" ]] || exit 1
[[ "${_MOLE_TRASH_BATCH_MOVED_PATHS[0]}" == "$first" ]] || exit 1
grep -Fxq "$first" "$fixture/trace" || exit 1
grep -Fxq "$second" "$fixture/trace" || exit 1
if [[ "$SINK" == direct && $PROBE_RC -eq 1 ]]; then
    [[ ! -e "$third" && ${#_MOLE_TRASH_BATCH_MOVED_PATHS[@]} -eq 2 ]] || exit 1
    grep -Fxq "$third" "$fixture/trace" || exit 1
else
    [[ -d "$third" && ${#_MOLE_TRASH_BATCH_MOVED_PATHS[@]} -eq 1 ]] || exit 1
    ! grep -Fxq "$third" "$fixture/trace" || exit 1
fi
[[ -z "$_MOLE_TRASH_MOVE_EXPECTED_PATH" && -z "$_MOLE_TRASH_MOVE_EXPECTED_PARENT" &&
    -z "$_MOLE_TRASH_MOVE_EXPECTED_PARENT_ID" && -z "$_MOLE_TRASH_MOVE_EXPECTED_TARGET_ID" ]] || exit 1
EOF
            [ "$status" -eq 0 ] || { echo "sink=$sink probe=$probe_rc: $output"; failures=$((failures + 1)); }
        done
    done
    [ "$failures" -eq 0 ]
}

@test "Finder Automation denial is explained after an earlier generic privacy refusal (#1644)" {
    export _MOLE_PRIVACY_DENIED_WARNED=1
    run_finder_result_fixture 1
    [[ "$output" == *"Privacy & Security > Automation"* ]] || return 1
    [[ "$output" == *"RC=1"* ]] || return 1
    [[ -d "$SANDBOX/FinderFixture.app" ]] || return 1
}


@test "direct Trash batch shares user values while checking every destination" {
    run env PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
export HOME="$SANDBOX/home"
mkdir -p "$HOME/.Trash" "$SANDBOX/targets"
chmod 700 "$HOME/.Trash"
source "$PROJECT_ROOT/lib/core/common.sh"
unset MOLE_TEST_NO_AUTH MOLE_TEST_MODE MOLE_TEST_TRASH_DIR
for i in 1 2 3; do touch "$SANDBOX/targets/item-$i"; done
get_invoking_uid() { echo uid >> "$SANDBOX/uid-calls"; id -u; }
get_invoking_gid() { echo gid >> "$SANDBOX/gid-calls"; id -g; }
chmod() { echo mode >> "$SANDBOX/chmod-calls"; command chmod "$@"; }
date() { echo date >> "$SANDBOX/date-calls"; command date "$@"; }
_mole_move_to_trash_batch "$SANDBOX/targets/item-1" "$SANDBOX/targets/item-2" "$SANDBOX/targets/item-3" || exit 1
[[ ${#_MOLE_TRASH_BATCH_MOVED_PATHS[@]} -eq 3 ]] || exit 1
[[ $(wc -l < "$SANDBOX/uid-calls") -eq 1 && $(wc -l < "$SANDBOX/gid-calls") -eq 1 ]] || exit 1
[[ ! -e "$SANDBOX/chmod-calls" && ! -e "$SANDBOX/date-calls" ]] || exit 1
[[ -f "$HOME/.Trash/item-1" && -f "$HOME/.Trash/item-3" ]] || exit 1
printf 'shared-user-values guarded-moves\n'
EOF
    [ "$status" -eq 0 ]
    [[ "$output" == *"shared-user-values guarded-moves"* ]]
}

@test "direct Trash batch repairs permissions changed between items" {
    run env PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
export HOME="$SANDBOX/home"
mkdir -p "$HOME/.Trash" "$SANDBOX/targets"
chmod 700 "$HOME/.Trash"
source "$PROJECT_ROOT/lib/core/common.sh"
unset MOLE_TEST_NO_AUTH MOLE_TEST_MODE MOLE_TEST_TRASH_DIR
for i in 1 2; do touch "$SANDBOX/targets/item-$i"; done
mv() {
    command mv "$@" || return $?
    if [[ "$2" == "$SANDBOX/targets/item-1" ]]; then
        command chmod 755 "$HOME/.Trash"
    fi
}
_mole_move_to_trash_batch "$SANDBOX/targets/item-1" "$SANDBOX/targets/item-2" || exit 1
[[ ${#_MOLE_TRASH_BATCH_MOVED_PATHS[@]} -eq 2 ]] || exit 1
[[ $(stat -f%Lp "$HOME/.Trash") == 700 ]] || exit 1
printf 'destination-rechecked\n'
EOF
    [ "$status" -eq 0 ]
    [[ "$output" == *"destination-rechecked"* ]]
}


@test "direct Trash batch rejects destination symlink introduced between moves" {
    run env PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
export HOME="$SANDBOX/home"
mkdir -p "$HOME/.Trash" "$SANDBOX/targets" "$SANDBOX/redirected"
source "$PROJECT_ROOT/lib/core/common.sh"
unset MOLE_TEST_NO_AUTH MOLE_TEST_MODE MOLE_TEST_TRASH_DIR
for i in 1 2; do touch "$SANDBOX/targets/item-$i"; done
eval "$(declare -f _mole_move_path_to_user_trash | sed '1s/_mole_move_path_to_user_trash/_fixture_move_to_trash/')"
_mole_move_path_to_user_trash() {
    _fixture_move_to_trash "$@" || return $?
    if [[ "$1" == "$SANDBOX/targets/item-1" ]]; then
        command mv "$HOME/.Trash" "$HOME/kept-trash"
        ln -s "$SANDBOX/redirected" "$HOME/.Trash"
    fi
    return 0
}
rc=0
_mole_move_to_trash_batch "$SANDBOX/targets/item-1" "$SANDBOX/targets/item-2" || rc=$?
[[ $rc == 1 && ${#_MOLE_TRASH_BATCH_MOVED_PATHS[@]} -eq 1 ]] || exit 1
[[ -f "$HOME/kept-trash/item-1" && -f "$SANDBOX/targets/item-2" ]] || exit 1
[[ ! -e "$SANDBOX/redirected/item-2" ]] || exit 1
printf 'destination-swap-refused\n'
EOF
    [ "$status" -eq 0 ]
    [[ "$output" == *"destination-swap-refused"* ]]
}
