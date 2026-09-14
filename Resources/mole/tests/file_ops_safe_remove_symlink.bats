#!/usr/bin/env bats

# Tests for safe_remove_symlink in lib/core/file_ops.sh.
# The helper removes a symlink itself (never its target), refuses anything
# that is not a symlink, runs the deletion validator, and honours dry-run.

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT
}

setup() {
    SANDBOX="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-symlink.XXXXXX")"
    export SANDBOX
    export MOLE_DELETE_LOG="$SANDBOX/deletions.log"
    export MOLE_TEST_NO_AUTH=1
    unset MOLE_DRY_RUN
}

teardown() {
    rm -rf "$SANDBOX"
}

prelude() {
    cat <<EOF
set -euo pipefail
export MOLE_DELETE_LOG="$MOLE_DELETE_LOG"
export MOLE_TEST_NO_AUTH=1
source "$PROJECT_ROOT/lib/core/common.sh"
EOF
}

@test "safe_remove_symlink removes the link but preserves its target" {
    local target="$SANDBOX/real_dir"
    local link="$SANDBOX/link_to_dir"
    mkdir -p "$target"
    printf 'keep me' > "$target/data.txt"
    ln -s "$target" "$link"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
safe_remove_symlink "$link"
EOF

    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    [[ ! -L "$link" ]] || { echo "link survived"; return 1; }
    # The critical safety property: the target and its contents are untouched.
    [[ -d "$target" && -f "$target/data.txt" ]] || { echo "target was damaged"; return 1; }
}

@test "safe_remove_symlink refuses a regular file" {
    local victim="$SANDBOX/not_a_link"
    printf 'data' > "$victim"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
safe_remove_symlink "$victim"
EOF

    [ "$status" -ne 0 ] || { echo "should have refused a non-symlink"; return 1; }
    [[ -f "$victim" ]] || { echo "non-symlink was deleted"; return 1; }
}

@test "safe_remove_symlink honours dry-run and keeps the link" {
    local target="$SANDBOX/dry_target"
    local link="$SANDBOX/dry_link"
    mkdir -p "$target"
    ln -s "$target" "$link"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
export MOLE_DRY_RUN=1
safe_remove_symlink "$link"
EOF

    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    [[ -L "$link" ]] || { echo "dry-run deleted the link"; return 1; }
}

@test "safe_remove_symlink honours the cleanup whitelist" {
    local target="$SANDBOX/whitelist_target"
    local link="$SANDBOX/whitelist_link"
    mkdir -p "$target"
    ln -s "$target" "$link"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
is_path_whitelisted() { [[ "\$1" == "$link" ]]; }
safe_remove_symlink "$link"
EOF

    [ "$status" -ne 0 ] || { echo "whitelisted link reported removal success"; return 1; }
    [[ -L "$link" ]] || { echo "whitelisted link was deleted"; return 1; }
    [[ -d "$target" ]] || { echo "symlink target was damaged"; return 1; }
}
