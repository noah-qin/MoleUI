#!/usr/bin/env bats

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT

    ORIGINAL_HOME="${HOME:-}"
    export ORIGINAL_HOME

    HOME="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-corepack.XXXXXX")"
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

# Regression: clean_corepack_cache must suppress corepack's interactive
# download prompt. Without COREPACK_ENABLE_DOWNLOAD_PROMPT=0 the command can
# block on stdin while its prompt is hidden by the > /dev/null 2>&1 redirect,
# so the section looks frozen until the timeout fires.
@test "clean_corepack_cache suppresses the corepack download prompt" {
    local log="$HOME/corepack-calls.log"
    : > "$log"
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" COREPACK_LOG="$log" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/dev.sh"
start_section_spinner() { :; }
stop_section_spinner() { :; }
note_activity() { :; }
# run_with_timeout normally execs the real binary, bypassing function mocks;
# override it so the corepack stub below is reachable and sees the env.
run_with_timeout() { shift; "$@"; }
clean_tool_cache() { shift 2; "$@"; }
safe_clean() { echo "safe_clean:$2"; }
# Log to a file rather than stdout: the --version detection call is wrapped in
# > /dev/null 2>&1, so stdout would hide it.
corepack() {
    echo "corepack:$*:prompt=${COREPACK_ENABLE_DOWNLOAD_PROMPT:-UNSET}" >> "$COREPACK_LOG"
}
export -f corepack
clean_corepack_cache
EOF

    [ "$status" -eq 0 ] || return 1
    local calls
    calls="$(cat "$log")"
    [[ "$calls" == *"corepack:--version:prompt=0"* ]] || return 1
    [[ "$calls" == *"corepack:cache clean:prompt=0"* ]] || return 1
    [[ "$calls" != *"prompt=UNSET"* ]] || return 1
}

# When corepack is not installed the cleanup must fall through to the safe
# local-path delete and never invoke corepack.
@test "clean_corepack_cache falls back to safe_clean without corepack" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" PATH="/usr/bin:/bin" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/dev.sh"
start_section_spinner() { :; }
stop_section_spinner() { :; }
note_activity() { :; }
run_with_timeout() { shift; "$@"; }
clean_tool_cache() { echo "clean_tool_cache:$1"; }
safe_clean() { echo "safe_clean:$2"; }
command() {
    if [[ "$1" == "-v" && "$2" == "corepack" ]]; then
        return 1
    fi
    builtin command "$@"
}
clean_corepack_cache
EOF

    [ "$status" -eq 0 ] || return 1
    [[ "$output" == *"safe_clean:Corepack cache"* ]] || return 1
    [[ "$output" != *"clean_tool_cache:Corepack cache"* ]] || return 1
}
