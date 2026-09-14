#!/usr/bin/env bats

setup_file() {
	PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
	export PROJECT_ROOT
}

@test "tty ownership helper distinguishes foreground and background processes" {
	if [[ "$(uname -s)" != "Darwin" || ! -x /usr/bin/expect || ! -x /usr/bin/perl ]]; then
		skip "macOS expect/perl required"
	fi

	run /usr/bin/expect "$PROJECT_ROOT/tests/uninstall_tty_foreground.exp" "$PROJECT_ROOT"

	[ "$status" -eq 0 ]
	[[ "$output" == *"TTY-STATE:foreground"* ]] || return 1
	[[ "$output" == *"TTY-STATE:background"* ]]
}

@test "completed uninstall checks tty ownership before countdown input" {
	run grep -n 'if ! mole_tty_is_foreground; then' "$PROJECT_ROOT/bin/uninstall.sh"

	[ "$status" -eq 0 ]
}

@test "tty ownership helper permits non-terminal input" {
	run /bin/bash -c '
        set -euo pipefail
        source "$1/lib/core/timeout.sh"
        mole_tty_is_foreground
    ' _ "$PROJECT_ROOT"

	[ "$status" -eq 0 ]
}
