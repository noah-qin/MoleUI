#!/usr/bin/env bash
# shellcheck shell=bash
# Shared Bats setup. Load with `load helpers/common` at the top of a test file.
#
# Loading this file also puts a directory of fail-loud stubs on PATH, so a
# command a test must never run for real turns a forgotten mock into a red
# test instead of a host-dependent pass. See mole_test_install_unstubbed_path.

# PROJECT_ROOT for files that need nothing else from the shared setup.
mole_test_setup_project_root() {
	PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
	export PROJECT_ROOT
}

# setup_file boilerplate: PROJECT_ROOT, ORIGINAL_HOME, and a throwaway HOME
# created as tests/tmp-<name>.XXXXXX. scripts/test.sh sweeps orphaned
# tests/tmp-* directories left by killed runs, so keep that prefix.
mole_test_setup_home() {
	local name="${1:?mole_test_setup_home needs a directory name}"
	mole_test_setup_project_root

	ORIGINAL_HOME="${HOME:-}"
	export ORIGINAL_HOME

	HOME="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-${name}.XXXXXX")"
	export HOME
}

# teardown_file counterpart of mole_test_setup_home. Removes HOME only when
# it is one of ours, then restores the original.
mole_test_teardown_home() {
	if [[ "$HOME" == "${BATS_TEST_DIRNAME}/tmp-"* ]]; then
		rm -rf "$HOME" # SAFE: test-owned mktemp HOME under tests/tmp-*
	fi
	if [[ -n "${ORIGINAL_HOME:-}" ]]; then
		export HOME="$ORIGINAL_HOME"
	fi
}

# Source install.sh whole, so a function under test runs with every helper
# it calls today instead of an extracted copy that silently falls back when
# a helper is missing. install.sh dispatches only when executed or piped, so
# sourcing just loads definitions. Its top-level `set -euo pipefail` is undone
# by restoring the caller's shell options; its defaults (INSTALL_DIR, colors,
# log_*) land first, so call this before the test sets its own values and
# mocks. An optional path sources a patched copy instead.
mole_source_installer() {
	local _mole_installer_path="${1:-$PROJECT_ROOT/install.sh}"
	local _mole_installer_opts
	_mole_installer_opts="$(set +o)"
	# shellcheck source=/dev/null
	source "$_mole_installer_path"
	eval "$_mole_installer_opts"
}
export -f mole_source_installer

# Commands a test must never run against the real host. Each stub prints
# `UNSTUBBED <cmd> <args>` to stderr and exits 97. A test that needs one
# defines a shell function (functions win over PATH) or puts its own stub
# directory earlier on PATH. Production code that calls an absolute path such
# as /usr/bin/sudo bypasses these stubs by design.
MOLE_TEST_UNSTUBBED_COMMANDS=(sudo osascript launchctl mdfind brew xcrun)

# Put an executable test double for <name> first on PATH for the rest of this
# test, including `run env ... /bin/bash` children and `mole` subprocesses.
# Use it where a shell-function mock cannot reach: run_with_timeout hands its
# command to gtimeout, which execs a binary and never sees shell functions.
# The optional body is the script after the shebang; the default answers
# with no output and status 0.
mole_test_fake_command() {
	local name="${1:?mole_test_fake_command needs a command name}"
	local body="${2:-exit 0}"
	local fake_dir="$BATS_TEST_TMPDIR/fake-bin"
	mkdir -p "$fake_dir"
	printf '#!/bin/bash\n%s\n' "$body" > "$fake_dir/$name"
	chmod +x "$fake_dir/$name"
	case ":$PATH:" in
		*":$fake_dir:"*) ;;
		*) export PATH="$fake_dir:$PATH" ;;
	esac
}

mole_test_install_unstubbed_path() {
	# The first load happens while Bats counts tests, before any file tmpdir
	# exists; the setup_file and per-test loads follow with one set.
	[[ -n "${BATS_FILE_TMPDIR:-}" ]] || return 0
	local stub_dir="$BATS_FILE_TMPDIR/mole-unstubbed-bin"
	local cmd
	if [[ ! -d "$stub_dir" ]]; then
		mkdir -p "$stub_dir"
		for cmd in "${MOLE_TEST_UNSTUBBED_COMMANDS[@]}"; do
			cat > "$stub_dir/$cmd" << 'STUB'
#!/bin/bash
printf 'UNSTUBBED %s %s\n' "${0##*/}" "$*" >&2
exit 97
STUB
			chmod +x "$stub_dir/$cmd"
		done
	fi
	# Prepend once. A later setup_file or setup that puts its own stubs first
	# must stay ahead, so a per-test reload never moves this directory up.
	case ":$PATH:" in
		*":$stub_dir:"*) ;;
		*) export PATH="$stub_dir:$PATH" ;;
	esac
}

mole_test_install_unstubbed_path
