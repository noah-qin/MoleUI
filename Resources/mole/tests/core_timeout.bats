#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT
    export MO_DEBUG=0
}

@test "run_with_timeout: command completes before timeout" {
    result=$(/bin/bash -c "
        set -euo pipefail
        source '$PROJECT_ROOT/lib/core/timeout.sh'
        run_with_timeout 5 echo 'success'
    ")
    [[ "$result" == "success" ]]
}

@test "run_with_timeout: zero timeout runs command normally" {
    result=$(/bin/bash -c "
        set -euo pipefail
        source '$PROJECT_ROOT/lib/core/timeout.sh'
        run_with_timeout 0 echo 'no_timeout'
    ")
    [[ "$result" == "no_timeout" ]]
}

@test "run_with_timeout: invalid timeout runs command normally" {
    result=$(/bin/bash -c "
        set -euo pipefail
        source '$PROJECT_ROOT/lib/core/timeout.sh'
        run_with_timeout invalid echo 'no_timeout'
    ")
    [[ "$result" == "no_timeout" ]]
}

@test "run_with_timeout: negative timeout runs command normally" {
    result=$(/bin/bash -c "
        set -euo pipefail
        source '$PROJECT_ROOT/lib/core/timeout.sh'
        run_with_timeout -5 echo 'no_timeout'
    ")
    [[ "$result" == "no_timeout" ]]
}

@test "run_with_timeout: preserves command exit code on success" {
    /bin/bash -c "
        set -euo pipefail
        source '$PROJECT_ROOT/lib/core/timeout.sh'
        run_with_timeout 5 true
    "
    exit_code=$?
    [[ $exit_code -eq 0 ]]
}

@test "run_with_timeout: preserves command exit code on failure" {
    set +e
    /bin/bash -c "
        set +e
        source '$PROJECT_ROOT/lib/core/timeout.sh'
        run_with_timeout 5 false
        exit \$?
    "
    exit_code=$?
    set -e
    [[ $exit_code -eq 1 ]]
}

@test "run_with_timeout: returns 124 on timeout (if using gtimeout)" {
    if ! command -v gtimeout >/dev/null 2>&1 && ! command -v timeout >/dev/null 2>&1; then
        skip "gtimeout/timeout not available"
    fi

    set +e
    /bin/bash -c "
        set +e
        source '$PROJECT_ROOT/lib/core/timeout.sh'
        run_with_timeout 1 sleep 3
        exit \$?
    "
    exit_code=$?
    set -e
    [[ $exit_code -eq 124 ]]
}

@test "run_with_timeout: kills long-running command" {
    start_time=$(date +%s)
    set +e
    /bin/bash -c "
        set +e
        source '$PROJECT_ROOT/lib/core/timeout.sh'
        run_with_timeout 2 sleep 5
    " >/dev/null 2>&1
    set -e
    end_time=$(date +%s)
    duration=$((end_time - start_time))

    [[ $duration -lt 10 ]]
}

@test "run_with_timeout: handles fast-completing commands" {
    start_time=$(date +%s)
    /bin/bash -c "
        set -euo pipefail
        source '$PROJECT_ROOT/lib/core/timeout.sh'
        run_with_timeout 10 echo 'fast'
    " >/dev/null 2>&1
    end_time=$(date +%s)
    duration=$((end_time - start_time))

    [[ $duration -lt 3 ]]
}

@test "run_with_timeout: works in pipefail mode" {
    result=$(/bin/bash -c "
        set -euo pipefail
        source '$PROJECT_ROOT/lib/core/timeout.sh'
        run_with_timeout 5 echo 'pipefail_test'
    ")
    [[ "$result" == "pipefail_test" ]]
}

@test "run_with_timeout: doesn't cause unintended exits" {
    result=$(/bin/bash -c "
        set -euo pipefail
        source '$PROJECT_ROOT/lib/core/timeout.sh'
        run_with_timeout 5 true || true
        echo 'survived'
    ")
    [[ "$result" == "survived" ]]
}

@test "run_with_timeout: handles commands with arguments" {
    result=$(/bin/bash -c "
        set -euo pipefail
        source '$PROJECT_ROOT/lib/core/timeout.sh'
        run_with_timeout 5 echo 'arg1' 'arg2' 'arg3'
    ")
    [[ "$result" == "arg1 arg2 arg3" ]]
}

@test "run_with_timeout: handles commands with spaces in arguments" {
    result=$(/bin/bash -c "
        set -euo pipefail
        source '$PROJECT_ROOT/lib/core/timeout.sh'
        run_with_timeout 5 echo 'hello world'
    ")
    [[ "$result" == "hello world" ]]
}

@test "run_with_timeout: debug logging when MO_DEBUG=1" {
    output=$(/bin/bash -c "
        set -euo pipefail
        export MO_DEBUG=1
        source '$PROJECT_ROOT/lib/core/timeout.sh'
        run_with_timeout 5 echo 'test' 2>&1
    ")
    [[ "$output" =~ TIMEOUT ]]
}

@test "run_with_timeout: no debug logging when MO_DEBUG=0" {
    output=$(/bin/bash -c "
        set -euo pipefail
        export MO_DEBUG=0
        unset MO_TIMEOUT_INITIALIZED
        source '$PROJECT_ROOT/lib/core/timeout.sh'
        run_with_timeout 5 echo 'test'
    " 2>/dev/null)
    [[ "$output" == "test" ]]
}

@test "timeout.sh: prevents multiple sourcing" {
    result=$(/bin/bash -c "
        set -euo pipefail
        source '$PROJECT_ROOT/lib/core/timeout.sh'
        source '$PROJECT_ROOT/lib/core/timeout.sh'
        echo 'loaded'
    ")
    [[ "$result" == "loaded" ]]
}

@test "timeout.sh: sets MOLE_TIMEOUT_LOADED flag" {
    result=$(/bin/bash -c "
        set -euo pipefail
        source '$PROJECT_ROOT/lib/core/timeout.sh'
        echo \"\$MOLE_TIMEOUT_LOADED\"
    ")
    [[ "$result" == "1" ]]
}

@test "run_with_timeout: perl fallback preserves command exit code (#1003)" {
    if ! command -v perl > /dev/null 2>&1; then
        skip "perl not available"
    fi
    set +e
    /bin/bash -c "
        set +e
        source '$PROJECT_ROOT/lib/core/timeout.sh'
        MO_TIMEOUT_BIN=''
        MO_TIMEOUT_PERL_BIN=\"\$(command -v perl)\"
        run_with_timeout 5 sh -c 'exit 7'
        exit \$?
    "
    exit_code=$?
    set -e
    [[ $exit_code -eq 7 ]]
}

@test "run_with_timeout: perl fallback kills long-running command (#1003)" {
    if ! command -v perl > /dev/null 2>&1; then
        skip "perl not available"
    fi
    start_time=$(date +%s)
    set +e
    /bin/bash -c "
        set +e
        source '$PROJECT_ROOT/lib/core/timeout.sh'
        MO_TIMEOUT_BIN=''
        MO_TIMEOUT_PERL_BIN=\"\$(command -v perl)\"
        run_with_timeout 2 sleep 8
    " > /dev/null 2>&1
    set -e
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    [[ $duration -lt 7 ]]
}

@test "run_with_timeout: perl fallback cleans child when its caller dies" {
    if [[ "$(uname -s)" != "Darwin" || ! -x /usr/bin/perl ]]; then
        skip "macOS perl required"
    fi

    local child_pid_file="$BATS_TEST_TMPDIR/timeout-child.pid"
    local caller_pid=""
    local perl_pid=""
    local child_pid=""

    /bin/bash "$PROJECT_ROOT/tests/timeout_parent_death_fixture.sh" \
        "$PROJECT_ROOT" "$child_pid_file" > /dev/null 2>&1 &
    caller_pid=$!

    for _ in {1..50}; do
        [[ -s "$child_pid_file" ]] && break
        /bin/sleep 0.1
    done
    [[ -s "$child_pid_file" ]] || {
        kill -KILL "$caller_pid" 2> /dev/null || true
        return 1
    }

    child_pid=$(cat "$child_pid_file")
    perl_pid=$(pgrep -P "$caller_pid" -x perl 2> /dev/null | head -1 || true)
    [[ "$child_pid" =~ ^[0-9]+$ && "$perl_pid" =~ ^[0-9]+$ ]] || {
        kill -KILL "$caller_pid" "$child_pid" 2> /dev/null || true
        return 1
    }

    kill -TERM "$caller_pid"
    for _ in {1..50}; do
        if ! kill -0 "$perl_pid" 2> /dev/null && ! kill -0 "$child_pid" 2> /dev/null; then
            break
        fi
        /bin/sleep 0.1
    done

    local leaked=0
    if kill -0 "$perl_pid" 2> /dev/null || kill -0 "$child_pid" 2> /dev/null; then
        leaked=1
        kill -KILL "$perl_pid" "$child_pid" 2> /dev/null || true
    fi
    kill -KILL "$caller_pid" 2> /dev/null || true
    wait "$caller_pid" 2> /dev/null || true

    [ "$leaked" -eq 0 ]
}

# setsid() in the perl fallback strips the controlling terminal, which breaks
# nested sudo inside brew cask uninstall scripts (issue #1003). The fallback must
# use setpgid to keep the tty while still enabling process-group kill. This guards
# against a regression that is otherwise only observable on a real terminal.
@test "timeout.sh: perl fallback must not detach the controlling tty (#1003)" {
    # Match call statements at line start, not the comments that explain why
    # setsid is avoided (those mention "setsid()" mid-line and would false-positive).
    run grep -nE '^[[:space:]]*setsid[[:space:]]*\(' "$PROJECT_ROOT/lib/core/timeout.sh"
    [ "$status" -ne 0 ]
    run grep -nE '^[[:space:]]*setpgid[[:space:]]*\(' "$PROJECT_ROOT/lib/core/timeout.sh"
	[ "$status" -eq 0 ]
}

@test "run_with_timeout: perl fallback keeps tty reads in foreground (#1201)" {
	if [[ "$(uname -s)" != "Darwin" || ! -x /usr/bin/expect || ! -x /usr/bin/perl ]]; then
		skip "macOS expect/perl required"
	fi

	run /usr/bin/expect "$PROJECT_ROOT/tests/timeout_tty_read.exp" "$PROJECT_ROOT"

	[ "$status" -eq 0 ]
	[[ "$output" == *"READ:typed-value"* ]]
}

@test "run_with_timeout: perl fallback restores tty after timeout (#1201)" {
	if [[ "$(uname -s)" != "Darwin" || ! -x /usr/bin/expect || ! -x /usr/bin/perl ]]; then
		skip "macOS expect/perl required"
	fi

	run /usr/bin/expect "$PROJECT_ROOT/tests/timeout_tty_restore.exp" "$PROJECT_ROOT"

	[ "$status" -eq 0 ]
	[[ "$output" == *"TIMEOUT:124"* ]] || return 1
	[[ "$output" == *"READ-AFTER:typed-after"* ]]
}

# Issue #1222: the perl fallback hands the controlling terminal to its timed
# child whenever stdin is a tty (the #1201 behaviour). When it is invoked from a
# background metadata/scan worker in bin/uninstall.sh that still has the tty on
# stdin, that handoff steals the foreground process group from the foreground
# script, which then stops with SIGTTIN at the confirmation prompt. Redirecting
# the worker's stdin from /dev/null makes -t STDIN false and skips the handoff.
# These two tests pin both halves of the contract: the handoff still happens for
# interactive (tty) callers, and never happens once stdin is /dev/null.
_tty_bg_field() {
	# Extract NAME=<digits> from the fixture output (single line each).
	printf '%s\n' "$2" | sed -n "s/.*${1}=\\([0-9][0-9]*\\).*/\\1/p" | head -1
}

@test "run_with_timeout: perl fallback hands tty to child when stdin is a tty (#1201/#1222)" {
	if [[ "$(uname -s)" != "Darwin" || ! -x /usr/bin/expect || ! -x /usr/bin/perl ]]; then
		skip "macOS expect/perl required"
	fi

	run /usr/bin/expect "$PROJECT_ROOT/tests/timeout_tty_background.exp" "$PROJECT_ROOT" tty

	[ "$status" -eq 0 ] || return 1
	local child fg caller
	child=$(_tty_bg_field CHILD_PGRP "$output")
	fg=$(_tty_bg_field FG "$output")
	caller=$(_tty_bg_field CALLER_PGRP "$output")
	[[ -n "$child" && -n "$fg" && -n "$caller" ]] || return 1
	# The timed child captured the terminal's foreground process group.
	[ "$fg" = "$child" ] || return 1
	[ "$fg" != "$caller" ] || return 1
}

@test "run_with_timeout: perl fallback keeps tty with caller when stdin is /dev/null (#1222)" {
	if [[ "$(uname -s)" != "Darwin" || ! -x /usr/bin/expect || ! -x /usr/bin/perl ]]; then
		skip "macOS expect/perl required"
	fi

	run /usr/bin/expect "$PROJECT_ROOT/tests/timeout_tty_background.exp" "$PROJECT_ROOT" devnull

	[ "$status" -eq 0 ] || return 1
	local child fg caller
	child=$(_tty_bg_field CHILD_PGRP "$output")
	fg=$(_tty_bg_field FG "$output")
	caller=$(_tty_bg_field CALLER_PGRP "$output")
	[[ -n "$child" && -n "$fg" && -n "$caller" ]] || return 1
	# No handoff: the terminal's foreground group stayed with the caller.
	[ "$fg" = "$caller" ] || return 1
	[ "$fg" != "$child" ] || return 1
}

# Guard the actual call sites: background uninstall workers must redirect stdin
# from /dev/null. Without it the Perl timeout fallback can steal the terminal
# from a background worker and suspend the foreground prompt with SIGTTIN.
@test "uninstall: background timeout workers redirect stdin (#1222)" {
	# Disowned metadata-refresh subshell close.
	run grep -nE '^[[:space:]]*\)[[:space:]]*>[[:space:]]*/dev/null[[:space:]]+2>&1[[:space:]]+<[[:space:]]*/dev/null[[:space:]]*&[[:space:]]*$' "$PROJECT_ROOT/bin/uninstall.sh"
	[ "$status" -eq 0 ] || return 1
	# Parallel scan workers.
	run grep -nE 'process_app_metadata[[:space:]].*<[[:space:]]*/dev/null[[:space:]]*&[[:space:]]*$' "$PROJECT_ROOT/bin/uninstall.sh"
	[ "$status" -eq 0 ] || return 1
	# Post-uninstall work: Homebrew autoremove and LaunchServices/Dock refresh.
	run grep -cE '^[[:space:]]*\)[[:space:]]*>[[:space:]]*/dev/null[[:space:]]+2>&1[[:space:]]+<[[:space:]]*/dev/null[[:space:]]*&[[:space:]]*$' "$PROJECT_ROOT/lib/uninstall/batch.sh"
	[ "$status" -eq 0 ] || return 1
	[ "$output" -ge 2 ] || return 1
}

@test "run_with_timeout: shell fallback preserves caller INT trap" {
    result=$(/bin/bash -c "
        set -euo pipefail
        source '$PROJECT_ROOT/lib/core/timeout.sh'
        MO_TIMEOUT_BIN=''
        MO_TIMEOUT_PERL_BIN=''
        trap 'echo caller-trap' INT
        run_with_timeout 2 true
        trap -p INT
    ")
    [[ "$result" == *"caller-trap"* ]]
}

@test "run_with_timeout: shell fallback cleans up watchdog sleep" {
    /bin/bash -c "
        set -euo pipefail
        source '$PROJECT_ROOT/lib/core/timeout.sh'
        MO_TIMEOUT_BIN=''
        MO_TIMEOUT_PERL_BIN=''
        run_with_timeout 287 true
        sleep 0.1
        leaked=''
        for pid in \$(pgrep -x sleep 2>/dev/null || true); do
            command_line=\$(ps -p \"\$pid\" -o command= 2>/dev/null || true)
            if [[ \"\$command_line\" == 'sleep 287' ]]; then
                leaked=\"\$pid\"
                kill \"\$pid\" 2>/dev/null || true
            fi
        done
        [[ -z \"\$leaked\" ]] || return 1
    "
}

# A directory-sizing `du` on a stalled network mount or a huge tree wedges the
# whole scan: it has no internal bound and the caller usually pipes it into a
# command substitution that just waits. Every `du -s*` in lib/ and bin/ must
# therefore run under run_with_timeout or the shared bounded sudo helper. This
# test pins that so a new sizing site cannot be added unbounded.
@test "every du sizing call in lib/ and bin/ runs under run_with_timeout" {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    unbounded=""
    while IFS=: read -r file line text; do
        [[ "$text" =~ ^[[:space:]]*# ]] && continue
        local first_line=$((line > 2 ? line - 2 : 1))
        local context=""
        context=$(sed -n "${first_line},${line}p" "$file")
        if ! grep -Eq 'run_with_timeout|_mole_bounded_sudo' <<< "$context"; then
            unbounded+="${file}:${line}:${text}"$'\n'
        fi
    done < <(grep -rn -- 'du -s' "$PROJECT_ROOT/lib" "$PROJECT_ROOT/bin" || true)
    if [[ -n "$unbounded" ]]; then
        echo "Unbounded du call sites:" >&2
        echo "$unbounded" >&2
        return 1
    fi
}
