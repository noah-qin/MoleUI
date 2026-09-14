#!/usr/bin/env bats

# Tests for get_path_size_kb in lib/core/file_ops.sh.
# Exercises the allocated-block stat fast-path for regular files / symlinks
# and the du fallback for directories, plus error and edge cases. Values are
# compared with `du -skP` so every path type keeps one physical disk-occupancy
# basis.

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT
}

setup() {
    SANDBOX="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-fileops-size.XXXXXX")"
    export SANDBOX
    export MOLE_TEST_NO_AUTH=1
}

teardown() {
    rm -rf "$SANDBOX"
}

prelude() {
    cat << EOF
set -euo pipefail
export MOLE_TEST_NO_AUTH=1
source "$PROJECT_ROOT/lib/core/common.sh"
EOF
}

@test "get_path_size_kb returns 0 for empty path" {
    run /bin/bash --noprofile --norc << EOF
$(prelude)
get_path_size_kb ""
EOF
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}

@test "get_path_size_kb returns 0 for non-existent path" {
    run /bin/bash --noprofile --norc << EOF
$(prelude)
get_path_size_kb "$SANDBOX/does-not-exist"
EOF
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}

@test "get_path_size_kb returns 0 for empty file" {
    : > "$SANDBOX/empty"
    run /bin/bash --noprofile --norc << EOF
$(prelude)
get_path_size_kb "$SANDBOX/empty"
EOF
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}

@test "get_path_size_kb matches disk occupancy for sub-KB files" {
    dd if=/dev/zero of="$SANDBOX/small" bs=500 count=1 2> /dev/null
    expected=$(du -skP "$SANDBOX/small" | awk '{print $1}')
    run /bin/bash --noprofile --norc << EOF
$(prelude)
get_path_size_kb "$SANDBOX/small"
EOF
    [ "$status" -eq 0 ]
    [ "$output" = "$expected" ]
}

@test "get_path_size_kb matches disk occupancy for 1024-byte file" {
    dd if=/dev/zero of="$SANDBOX/onek" bs=1024 count=1 2> /dev/null
    expected=$(du -skP "$SANDBOX/onek" | awk '{print $1}')
    run /bin/bash --noprofile --norc << EOF
$(prelude)
get_path_size_kb "$SANDBOX/onek"
EOF
    [ "$status" -eq 0 ]
    [ "$output" = "$expected" ]
}

@test "get_path_size_kb matches disk occupancy for odd byte counts" {
    dd if=/dev/zero of="$SANDBOX/odd" bs=50000 count=1 2> /dev/null
    expected=$(du -skP "$SANDBOX/odd" | awk '{print $1}')
    run /bin/bash --noprofile --norc << EOF
$(prelude)
get_path_size_kb "$SANDBOX/odd"
EOF
    [ "$status" -eq 0 ]
    [ "$output" = "$expected" ]
}

@test "get_path_size_kb does not follow symlinks" {
    # 100 KB target, symlink should report its own (tiny) size, not 100 KB.
    dd if=/dev/zero of="$SANDBOX/target" bs=1024 count=100 2> /dev/null
    ln -s "$SANDBOX/target" "$SANDBOX/link"

    target_kb=$(/bin/bash --noprofile --norc << EOF
$(prelude)
get_path_size_kb "$SANDBOX/target"
EOF
)
    link_kb=$(/bin/bash --noprofile --norc << EOF
$(prelude)
get_path_size_kb "$SANDBOX/link"
EOF
)

    expected_target=$(du -skP "$SANDBOX/target" | awk '{print $1}')
    [ "$target_kb" = "$expected_target" ]
    # Symlink path strings are short, so link size rounds to 1 KB or 0.
    # Either is acceptable; what must NOT happen is the link reporting the
    # 100 KB target size.
    [ "$link_kb" -lt 10 ]
}

@test "get_path_size_kb still returns 0 for broken symlinks" {
    ln -s "$SANDBOX/missing" "$SANDBOX/broken"
    run /bin/bash --noprofile --norc << EOF
$(prelude)
get_path_size_kb "$SANDBOX/broken"
EOF
    [ "$status" -eq 0 ]
    # -e on a broken symlink returns false, so the early return triggers.
    [ "$output" = "0" ]
}

@test "get_path_size_kb sums directory contents recursively" {
    mkdir -p "$SANDBOX/dir/sub"
    dd if=/dev/zero of="$SANDBOX/dir/a" bs=1024 count=10 2> /dev/null
    dd if=/dev/zero of="$SANDBOX/dir/sub/b" bs=1024 count=20 2> /dev/null

    run /bin/bash --noprofile --norc << EOF
$(prelude)
get_path_size_kb "$SANDBOX/dir"
EOF
    [ "$status" -eq 0 ]
    # Should be at least the sum of the two files (30 KB). Filesystem
    # overhead may push it slightly higher, so use >= rather than ==.
    [ "$output" -ge 30 ]
}

@test "get_path_size_kb handles whitespace in paths" {
    local quirky="$SANDBOX/dir with spaces"
    mkdir -p "$quirky"
    dd if=/dev/zero of="$quirky/payload" bs=1024 count=5 2> /dev/null
    expected=$(du -skP "$quirky/payload" | awk '{print $1}')

    run /bin/bash --noprofile --norc << EOF
$(prelude)
get_path_size_kb "$quirky/payload"
EOF
    [ "$status" -eq 0 ]
    [ "$output" = "$expected" ]
}

@test "get_path_size_kb propagates metadata stat and du timeouts" {
    mkdir -p "$SANDBOX/Stalled.app" "$SANDBOX/stalled-dir"
    printf 'x\n' > "$SANDBOX/stalled-file"

    run env PROJECT_ROOT="$PROJECT_ROOT" SANDBOX="$SANDBOX" \
        /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
run_with_timeout() { return 124; }

for target in "$SANDBOX/Stalled.app" "$SANDBOX/stalled-file" "$SANDBOX/stalled-dir"; do
    size=""
    rc=0
    size=$(get_path_size_kb "$target") || rc=$?
    printf 'RC=%s SIZE=%s TARGET=%s\n' "$rc" "$size" "${target##*/}"
    [[ $rc -eq 124 && -z "$size" ]] || exit 1
done
EOF

    [ "$status" -eq 0 ] || {
        echo "$output"
        return 1
    }
    [[ "$output" == *"RC=124 SIZE= TARGET=Stalled.app"* ]] || return 1
    [[ "$output" == *"RC=124 SIZE= TARGET=stalled-file"* ]] || return 1
    [[ "$output" == *"RC=124 SIZE= TARGET=stalled-dir"* ]]
}

@test "get_path_size_kb uses physical metadata for app bundles" {
    mkdir -p "$SANDBOX/Sized.app"

    run env PROJECT_ROOT="$PROJECT_ROOT" SANDBOX="$SANDBOX" \
        /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
run_with_timeout() {
    shift
    if [[ "$1" == "mdls" && "$*" == *"kMDItemPhysicalSize"* ]]; then
        printf '4096\n'
        return 0
    fi
    if [[ "$1" == "mdls" && "$*" == *"kMDItemLogicalSize"* ]]; then
        printf '8192\n'
        return 0
    fi
    return 1
}

get_path_size_kb "$SANDBOX/Sized.app"
EOF

    [ "$status" -eq 0 ] || return 1
    [ "$output" = "4" ]
}

@test "get_path_size_kb rejects partial du output on scan failure" {
    mkdir -p "$SANDBOX/partial-dir"

    run env PROJECT_ROOT="$PROJECT_ROOT" SANDBOX="$SANDBOX" \
        /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
run_with_timeout() {
    shift
    if [[ "$1" == "du" ]]; then
        printf '777\t%s\n' "$SANDBOX/partial-dir"
        return 1
    fi
    command "$@"
}

size=""
rc=0
size=$(get_path_size_kb "$SANDBOX/partial-dir") || rc=$?
printf 'RC=%s SIZE=%s\n' "$rc" "$size"
[[ $rc -eq 1 && -z "$size" ]] || exit 1
EOF

    [ "$status" -eq 0 ] || return 1
    [ "$output" = "RC=1 SIZE=" ]
}
