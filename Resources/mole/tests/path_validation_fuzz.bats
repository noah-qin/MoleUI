#!/usr/bin/env bats
# Property-based test: every path in tests/fuzz_corpus/dangerous_paths.txt
# MUST be rejected by validate_path_for_deletion. If even one passes,
# the corpus has caught a real safety regression - investigate, do not
# weaken the corpus.

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT

    ORIGINAL_HOME="${HOME:-}"
    export ORIGINAL_HOME
    HOME="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-path-fuzz.XXXXXX")"
    export HOME
    mkdir -p "$HOME"

    CORPUS="$BATS_TEST_DIRNAME/fuzz_corpus/dangerous_paths.txt"
    export CORPUS
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
    if [[ "$HOME" != "${BATS_TEST_DIRNAME}/tmp-"* ]]; then
        printf 'FATAL: HOME is not a test temp dir: %s\n' "$HOME" >&2
        return 1
    fi
    # shellcheck source=lib/core/common.sh
    source "$PROJECT_ROOT/lib/core/common.sh"
}

@test "corpus file exists and is non-empty" {
    [ -f "$CORPUS" ]
    [ -s "$CORPUS" ]
}

@test "every dangerous path is rejected by validate_path_for_deletion" {
    [ -f "$CORPUS" ]

    local rejected=0
    local accepted=0
    local -a accepted_paths=()
    local line

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comments and blank lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$line" ]] && continue

        run /bin/bash --noprofile --norc -s -- "$line" <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
validate_path_for_deletion "$1"
EOF
        if [[ "$status" -eq 0 ]]; then
            accepted=$((accepted + 1))
            accepted_paths+=("$line")
        else
            rejected=$((rejected + 1))
        fi
    done < "$CORPUS"

    if [[ $accepted -gt 0 ]]; then
        printf 'FAIL: %d dangerous paths were accepted:\n' "$accepted" >&2
        printf '  %s\n' "${accepted_paths[@]}" >&2
    fi
    [ "$accepted" -eq 0 ]
    [ "$rejected" -ge 50 ]
}

@test "generated control-character paths are rejected" {
    run /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
validate_path_for_deletion $'/Users/me/with\nnewline'
EOF
    [ "$status" -eq 1 ]

    run /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
validate_path_for_deletion $'/Users/me/with\tab'
EOF
    [ "$status" -eq 1 ]
}

@test "property: an ancestor symlink into any critical root is always rejected" {
    # The string corpus cannot express this class: the path text is innocuous
    # and only the filesystem state makes it dangerous. Generate one case per
    # critical root instead, so a future refactor of the ancestor guard cannot
    # silently narrow it to a single hardcoded root.
    local sandbox
    sandbox="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-ancestor.XXXXXX")"

    # Only roots whose DESCENDANTS the policy denies. /var is deliberately not
    # here: /var/folders and friends are cleanable temp trees, so /var/x/y is
    # accepted literally too, and the symlinked form must stay consistent with
    # that (the guard is deny-only, it never invents a stricter policy).
    local root
    for root in /System /usr /bin /etc; do
        local link="$sandbox/link-${root//\//_}"
        ln -s "$root" "$link"
        # Victim sits directly under the redirected dir, so its parent (the
        # symlink) really resolves: this is the shape a hijacked cache root
        # takes, and the shape the guard must catch.
        run /bin/bash --noprofile --norc <<EOF
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
validate_path_for_deletion "$link/victim"
EOF
        if [ "$status" -eq 0 ]; then
            rm -rf "$sandbox"
            echo "ancestor symlink into $root was accepted"
            return 1
        fi
    done

    rm -rf "$sandbox"
}

@test "corpus has minimum coverage" {
    local active
    active=$(grep -cvE '^\s*(#|$)' "$CORPUS")
    # Lower bound prevents accidental corpus deletion from passing CI.
    [ "$active" -ge 50 ]
}
