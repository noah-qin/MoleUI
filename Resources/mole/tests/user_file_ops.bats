#!/usr/bin/env bats


setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT

    ORIGINAL_HOME="${HOME:-}"
    export ORIGINAL_HOME

    HOME="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-userfile.XXXXXX")"
    export HOME

    mkdir -p "$HOME"
}

teardown_file() {
    if [[ "$HOME" == "${BATS_TEST_DIRNAME}/tmp-"* ]]; then
        rm -rf "$HOME"
    fi
    if [[ -n "${ORIGINAL_HOME:-}" ]]; then
        export HOME="$ORIGINAL_HOME"
    fi
}

setup() {
    # Safety: refuse to operate on a real home directory.
    if [[ "$HOME" != "${BATS_TEST_DIRNAME}/tmp-"* ]]; then
        printf 'FATAL: HOME is not a test temp dir: %s\n' "$HOME" >&2
        return 1
    fi
    rm -rf "$HOME/.config" "$HOME/.cache"
    mkdir -p "$HOME"
}

@test "is_root_user detects non-root correctly" {
    result=$(/bin/bash -c "source '$PROJECT_ROOT/lib/core/base.sh'; is_root_user && echo 'root' || echo 'not-root'")
    [ "$result" = "not-root" ]
}

@test "get_invoking_uid returns numeric UID" {
    result=$(/bin/bash -c "source '$PROJECT_ROOT/lib/core/base.sh'; get_invoking_uid")
    [[ "$result" =~ ^[0-9]+$ ]]
}

@test "get_invoking_gid returns numeric GID" {
    result=$(/bin/bash -c "source '$PROJECT_ROOT/lib/core/base.sh'; get_invoking_gid")
    [[ "$result" =~ ^[0-9]+$ ]]
}

@test "get_invoking_home returns home directory" {
    result=$(/bin/bash -c "source '$PROJECT_ROOT/lib/core/base.sh'; get_invoking_home")
    [ -n "$result" ]
    [ -d "$result" ]
}

@test "prepare_mole_tmpdir uses writable TMPDIR when available" {
    local writable_tmp="$HOME/custom-tmp"
    mkdir -p "$writable_tmp"

    result=$(env HOME="$HOME" TMPDIR="$writable_tmp" /bin/bash -c "source '$PROJECT_ROOT/lib/core/base.sh'; prepare_mole_tmpdir")
    [ "$result" = "$writable_tmp" ]
}

@test "prepare_mole_tmpdir falls back to user cache when TMPDIR is not writable" {
    local blocked_tmp="$HOME/blocked-tmp"
    mkdir -p "$blocked_tmp"
    chmod 500 "$blocked_tmp"

    result=$(env HOME="$HOME" TMPDIR="$blocked_tmp" /bin/bash -c "source '$PROJECT_ROOT/lib/core/base.sh'; prepare_mole_tmpdir")
    [ "$result" = "$HOME/.cache/mole/tmp" ]
    [ -d "$HOME/.cache/mole/tmp" ]
}

@test "ensure_mole_temp_root caches the first resolved directory" {
    local first_tmp="$HOME/first-tmp"
    local second_tmp="$HOME/second-tmp"
    mkdir -p "$first_tmp" "$second_tmp"

    result=$(env HOME="$HOME" TMPDIR="$first_tmp" /bin/bash -c "
        source '$PROJECT_ROOT/lib/core/base.sh'
        ensure_mole_temp_root
        first=\$MOLE_RESOLVED_TMPDIR
        export TMPDIR='$second_tmp'
        ensure_mole_temp_root
        second=\$MOLE_RESOLVED_TMPDIR
        printf '%s|%s\n' \"\$first\" \"\$second\"
    ")

    [ "$result" = "$first_tmp|$first_tmp" ]
}

@test "cleanup_temp_files removes command-substitution temp files (#1203)" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/base.sh"

MOLE_RESOLVED_TMPDIR="$HOME/.cache/mole/tmp"
MOLE_TEMP_REGISTRY_FILE=""
export MOLE_RESOLVED_TMPDIR MOLE_TEMP_REGISTRY_FILE
mkdir -p "$MOLE_RESOLVED_TMPDIR"

temp_file=$(mktemp_file "subshell")
printf 'BEFORE:%s\n' "$([[ -f "$temp_file" ]] && echo exists || echo missing)"
cleanup_temp_files
printf 'AFTER:%s\n' "$([[ -f "$temp_file" ]] && echo leaked || echo cleaned)"
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"BEFORE:exists"* ]] || return 1
    [[ "$output" == *"AFTER:cleaned"* ]]
}

@test "a forked child does not adopt the parent temp registry" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -uo pipefail
source "$PROJECT_ROOT/lib/core/base.sh"

MOLE_RESOLVED_TMPDIR="$HOME/.cache/mole/tmp"
MOLE_TEMP_REGISTRY_FILE=""
export MOLE_RESOLVED_TMPDIR MOLE_TEMP_REGISTRY_FILE
mkdir -p "$MOLE_RESOLVED_TMPDIR"

# `mole` resolves the temp root at startup, so the registry path is exported
# from the main shell rather than from a command-substitution subshell.
ensure_mole_temp_root
parent_file=$(mktemp_file "parent-installer")
[[ -f "$parent_file" ]] || exit 1

# install.sh runs the freshly installed `mole --version` while `mo update`
# still holds its downloaded installer. That child inherits the exported
# registry path; adopting it would delete the parent's live temp files.
/bin/bash --noprofile --norc -c '
    source "$PROJECT_ROOT/lib/core/base.sh"
    printf "CHILD_ADOPTED:%s\n" "$MOLE_TEMP_REGISTRY_FILE"
    ensure_mole_temp_registry_file || exit 1
    printf "CHILD_OWNS:%s\n" "$MOLE_TEMP_REGISTRY_FILE"
    cleanup_temp_files
' || exit 1

printf 'PARENT_FILE:%s\n' "$([[ -f "$parent_file" ]] && echo kept || echo deleted)"
cleanup_temp_files
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"PARENT_FILE:kept"* ]] || return 1
    child_adopted=$(printf '%s\n' "$output" | sed -n 's/^CHILD_ADOPTED://p')
    child_owns=$(printf '%s\n' "$output" | sed -n 's/^CHILD_OWNS://p')
    [[ -n "$child_adopted" && -n "$child_owns" ]] || return 1
    [ "$child_adopted" != "$child_owns" ]
}

@test "cleanup_temp_files rejects registry paths outside the temp root (#1203)" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/base.sh"

MOLE_RESOLVED_TMPDIR="$HOME/.cache/mole/tmp"
MOLE_TEMP_REGISTRY_FILE="$MOLE_RESOLVED_TMPDIR/mole.registry.$$"
export MOLE_RESOLVED_TMPDIR MOLE_TEMP_REGISTRY_FILE
mkdir -p "$MOLE_RESOLVED_TMPDIR"

persistent_file="$HOME/.cache/mole/installed_apps_cache"
touch "$persistent_file"
printf '%s\n' "$persistent_file" > "$MOLE_TEMP_REGISTRY_FILE"

cleanup_temp_files
[[ -e "$persistent_file" ]] || exit 1

invalid_registry="$HOME/.cache/mole/not-a-temp-registry"
printf '%s\n' "$persistent_file" > "$invalid_registry"
MOLE_TEMP_REGISTRY_FILE="$invalid_registry"
cleanup_temp_files
[[ -e "$invalid_registry" ]] || exit 1
EOF

    [ "$status" -eq 0 ]
}

@test "prune_stale_mole_temp_files leaves persistent cache and fresh temps alone (#1203)" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" MOLE_TEMP_STALE_MINUTES=60 /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/base.sh"

temp_root="$HOME/.cache/mole/tmp"
old_temp="$temp_root/old-scan"
fresh_temp="$temp_root/current-scan"
old_spinner="$temp_root/.mole-spinner.old"
fresh_spinner="$temp_root/.mole-spinner.fresh"
persistent_cache="$HOME/.cache/mole/installed_apps_cache"
mkdir -p "$old_spinner" "$fresh_spinner"
touch "$old_temp" "$fresh_temp" "$persistent_cache"
touch "$old_spinner/message" "$fresh_spinner/message"
touch -t 202001010101 "$old_temp" "$old_spinner" "$persistent_cache"

prune_stale_mole_temp_files "$temp_root"

[[ ! -e "$old_temp" ]] || exit 1
[[ ! -e "$old_spinner" ]] || exit 1
[[ -e "$fresh_temp" ]] || exit 1
[[ -e "$fresh_spinner/message" ]] || exit 1
[[ -e "$persistent_cache" ]] || exit 1
EOF

    [ "$status" -eq 0 ]
}

@test "prepare_mole_tmpdir falls back to /tmp when TMPDIR and invoking home are unavailable" {
    result=$(env HOME="$HOME" TMPDIR="/var/empty" /bin/bash -c "
        source '$PROJECT_ROOT/lib/core/base.sh'
        get_invoking_home() { echo '/var/empty'; }
        prepare_mole_tmpdir
    ")

    [ "$result" = "/tmp" ]
}

@test "common.sh exports resolved TMPDIR for runtime callers" {
    local blocked_tmp="$HOME/common-blocked-tmp"
    mkdir -p "$blocked_tmp"
    chmod 500 "$blocked_tmp"

    result=$(env HOME="$HOME" TMPDIR="$blocked_tmp" /bin/bash -c "source '$PROJECT_ROOT/lib/core/common.sh'; printf '%s\n' \"\$TMPDIR\"")
    [ "$result" = "$HOME/.cache/mole/tmp" ]
}

@test "get_user_home returns home for valid user" {
    current_user="${USER:-$(whoami)}"
    result=$(/bin/bash -c "source '$PROJECT_ROOT/lib/core/base.sh'; get_user_home '$current_user'")
    [ -n "$result" ]
    [ -d "$result" ]
}

@test "get_user_home returns empty for invalid user" {
    result=$(/bin/bash -c "source '$PROJECT_ROOT/lib/core/base.sh'; get_user_home 'nonexistent_user_12345'")
    [ -z "$result" ] || [ "$result" = "~nonexistent_user_12345" ]
}

@test "ensure_user_dir creates simple directory" {
    test_dir="$HOME/.cache/test"
    /bin/bash -c "source '$PROJECT_ROOT/lib/core/base.sh'; ensure_user_dir '$test_dir'"
    [ -d "$test_dir" ]
}

@test "ensure_user_dir creates nested directory" {
    test_dir="$HOME/.config/mole/deep/nested/path"
    /bin/bash -c "source '$PROJECT_ROOT/lib/core/base.sh'; ensure_user_dir '$test_dir'"
    [ -d "$test_dir" ]
}

@test "ensure_user_dir handles tilde expansion" {
    /bin/bash -c "source '$PROJECT_ROOT/lib/core/base.sh'; ensure_user_dir '~/.cache/tilde-test'"
    [ -d "$HOME/.cache/tilde-test" ]
}

@test "ensure_user_dir is idempotent" {
    test_dir="$HOME/.cache/idempotent"
    /bin/bash -c "source '$PROJECT_ROOT/lib/core/base.sh'; ensure_user_dir '$test_dir'"
    /bin/bash -c "source '$PROJECT_ROOT/lib/core/base.sh'; ensure_user_dir '$test_dir'"
    [ -d "$test_dir" ]
}

@test "ensure_user_dir handles empty path gracefully" {
    run /bin/bash -c "source '$PROJECT_ROOT/lib/core/base.sh'; ensure_user_dir ''"
    [ "$status" -eq 0 ]
}

@test "ensure_user_dir preserves ownership for non-root users" {
    test_dir="$HOME/.cache/ownership-test"
    /bin/bash -c "source '$PROJECT_ROOT/lib/core/base.sh'; ensure_user_dir '$test_dir'"

    current_uid=$(id -u)
    dir_uid=$(/usr/bin/stat -f%u "$test_dir")
    [ "$dir_uid" = "$current_uid" ]
}


@test "ensure_user_file creates file and parent directories" {
    test_file="$HOME/.config/mole/test.log"
    /bin/bash -c "source '$PROJECT_ROOT/lib/core/base.sh'; ensure_user_file '$test_file'"
    [ -f "$test_file" ]
    [ -d "$(dirname "$test_file")" ]
}

@test "ensure_user_file handles tilde expansion" {
    /bin/bash -c "source '$PROJECT_ROOT/lib/core/base.sh'; ensure_user_file '~/.cache/tilde-file.txt'"
    [ -f "$HOME/.cache/tilde-file.txt" ]
}

@test "ensure_user_file is idempotent" {
    test_file="$HOME/.cache/idempotent.txt"
    /bin/bash -c "source '$PROJECT_ROOT/lib/core/base.sh'; ensure_user_file '$test_file'"
    echo "content" > "$test_file"
    /bin/bash -c "source '$PROJECT_ROOT/lib/core/base.sh'; ensure_user_file '$test_file'"
    [ -f "$test_file" ]
    [ "$(cat "$test_file")" = "content" ]
}

@test "ensure_user_file handles empty path gracefully" {
    run /bin/bash -c "source '$PROJECT_ROOT/lib/core/base.sh'; ensure_user_file ''"
    [ "$status" -eq 0 ]
}

@test "ensure_user_file creates deeply nested files" {
    test_file="$HOME/.config/deep/very/nested/structure/file.log"
    /bin/bash -c "source '$PROJECT_ROOT/lib/core/base.sh'; ensure_user_file '$test_file'"
    [ -f "$test_file" ]
}

@test "ensure_user_file preserves ownership for non-root users" {
    test_file="$HOME/.cache/file-ownership-test.txt"
    /bin/bash -c "source '$PROJECT_ROOT/lib/core/base.sh'; ensure_user_file '$test_file'"

    current_uid=$(id -u)
    file_uid=$(/usr/bin/stat -f%u "$test_file")
    [ "$file_uid" = "$current_uid" ]
}

@test "ensure_user_dir early stop optimization works" {
    test_dir="$HOME/.cache/perf/test/nested"
    /bin/bash -c "source '$PROJECT_ROOT/lib/core/base.sh'; ensure_user_dir '$test_dir'"

    /bin/bash -c "source '$PROJECT_ROOT/lib/core/base.sh'; ensure_user_dir '$test_dir'"
    [ -d "$test_dir" ]

    current_uid=$(id -u)
    dir_uid=$(/usr/bin/stat -f%u "$test_dir")
    [ "$dir_uid" = "$current_uid" ]
}

@test "ensure_user_dir and ensure_user_file work together" {
    cache_dir="$HOME/.cache/mole"
    cache_file="$cache_dir/integration_test.log"

    /bin/bash -c "source '$PROJECT_ROOT/lib/core/base.sh'; ensure_user_dir '$cache_dir'"
    /bin/bash -c "source '$PROJECT_ROOT/lib/core/base.sh'; ensure_user_file '$cache_file'"

    [ -d "$cache_dir" ]
    [ -f "$cache_file" ]
}

@test "multiple ensure_user_file calls in same directory" {
    /bin/bash -c "source '$PROJECT_ROOT/lib/core/base.sh'
        ensure_user_file '$HOME/.config/mole/file1.txt'
        ensure_user_file '$HOME/.config/mole/file2.txt'
        ensure_user_file '$HOME/.config/mole/file3.txt'
    "

    [ -f "$HOME/.config/mole/file1.txt" ]
    [ -f "$HOME/.config/mole/file2.txt" ]
    [ -f "$HOME/.config/mole/file3.txt" ]
}

@test "ensure functions handle concurrent calls safely" {
    /bin/bash -c "source '$PROJECT_ROOT/lib/core/base.sh'
        ensure_user_dir '$HOME/.cache/concurrent' &
        ensure_user_dir '$HOME/.cache/concurrent' &
        wait
    "

    [ -d "$HOME/.cache/concurrent" ]
}
