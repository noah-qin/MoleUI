#!/usr/bin/env bats

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT

    ORIGINAL_HOME="${HOME:-}"
    export ORIGINAL_HOME

    HOME="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-installers-home.XXXXXX")"
    export HOME

    mkdir -p "$HOME"

    if command -v fd > /dev/null 2>&1; then
        FD_AVAILABLE=1
    else
        FD_AVAILABLE=0
    fi
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
    export TERM="xterm-256color"
    export MO_DEBUG=0

    # Create standard scan directories
    mkdir -p "$HOME/Downloads"
    mkdir -p "$HOME/Desktop"
    mkdir -p "$HOME/Documents"
    mkdir -p "$HOME/Public"
    mkdir -p "$HOME/Library/Downloads"

    # Clear previous test files
    rm -rf "${HOME:?}/Downloads"/*
    rm -rf "${HOME:?}/Desktop"/*
    rm -rf "${HOME:?}/Documents"/*
}

require_fd() {
    [[ "${FD_AVAILABLE:-0}" -eq 1 ]]
}

@test "scan_installers_in_path (fd): finds .dmg files" {
    if ! require_fd; then
        return 0
    fi

    touch "$HOME/Downloads/Chrome.dmg"

    run /bin/bash -euo pipefail -c '
        export MOLE_TEST_MODE=1
        source "$1"
        scan_installers_in_path "$2"
    ' bash "$PROJECT_ROOT/bin/installer.sh" "$HOME/Downloads"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Chrome.dmg"* ]]
}

@test "scan_installers_in_path (fd): finds multiple installer types" {
    if ! require_fd; then
        return 0
    fi

    touch "$HOME/Downloads/App1.dmg"
    touch "$HOME/Downloads/App2.pkg"
    touch "$HOME/Downloads/App3.iso"
    touch "$HOME/Downloads/App.mpkg"

    run /bin/bash -euo pipefail -c '
        export MOLE_TEST_MODE=1
        source "$1"
        scan_installers_in_path "$2"
    ' bash "$PROJECT_ROOT/bin/installer.sh" "$HOME/Downloads"

    [ "$status" -eq 0 ]
    [[ "$output" == *"App1.dmg"* ]] || return 1
    [[ "$output" == *"App2.pkg"* ]] || return 1
    [[ "$output" == *"App3.iso"* ]] || return 1
    [[ "$output" == *"App.mpkg"* ]]
}

@test "scan_installers_in_path (fd): respects max depth" {
    if ! require_fd; then
        return 0
    fi

    mkdir -p "$HOME/Downloads/level1/level2/level3"
    touch "$HOME/Downloads/shallow.dmg"
    touch "$HOME/Downloads/level1/mid.dmg"
    touch "$HOME/Downloads/level1/level2/deep.dmg"
    touch "$HOME/Downloads/level1/level2/level3/too-deep.dmg"

    run /bin/bash -euo pipefail -c '
        export MOLE_TEST_MODE=1
        source "$1"
        scan_installers_in_path "$2"
    ' bash "$PROJECT_ROOT/bin/installer.sh" "$HOME/Downloads"

    [ "$status" -eq 0 ]
    # Default max depth is 2
    [[ "$output" == *"shallow.dmg"* ]] || return 1
    [[ "$output" == *"mid.dmg"* ]] || return 1
    [[ "$output" == *"deep.dmg"* ]] || return 1
    [[ "$output" != *"too-deep.dmg"* ]]
}

@test "scan_installers_in_path (fd): honors MOLE_INSTALLER_SCAN_MAX_DEPTH" {
    if ! require_fd; then
        return 0
    fi

    mkdir -p "$HOME/Downloads/level1"
    touch "$HOME/Downloads/top.dmg"
    touch "$HOME/Downloads/level1/nested.dmg"

    run env MOLE_INSTALLER_SCAN_MAX_DEPTH=1 /bin/bash -euo pipefail -c "
        export MOLE_TEST_MODE=1
        source \"\$1\"
        scan_installers_in_path \"\$2\"
    " bash "$PROJECT_ROOT/bin/installer.sh" "$HOME/Downloads"

    [ "$status" -eq 0 ]
    [[ "$output" == *"top.dmg"* ]] || return 1
    [[ "$output" != *"nested.dmg"* ]]
}

@test "scan_installers_in_path (fd): handles non-existent directory" {
    if ! require_fd; then
        return 0
    fi

    run /bin/bash -euo pipefail -c '
        export MOLE_TEST_MODE=1
        source "$1"
        scan_installers_in_path "$2"
    ' bash "$PROJECT_ROOT/bin/installer.sh" "$HOME/NonExistent"

    [ "$status" -eq 0 ]
    [[ -z "$output" ]]
}

@test "scan_installers_in_path (fd): ignores non-installer files" {
    if ! require_fd; then
        return 0
    fi

    touch "$HOME/Downloads/document.pdf"
    touch "$HOME/Downloads/image.jpg"
    touch "$HOME/Downloads/archive.tar.gz"
    touch "$HOME/Downloads/Installer.dmg"

    run /bin/bash -euo pipefail -c '
        export MOLE_TEST_MODE=1
        source "$1"
        scan_installers_in_path "$2"
    ' bash "$PROJECT_ROOT/bin/installer.sh" "$HOME/Downloads"

    [ "$status" -eq 0 ]
    [[ "$output" != *"document.pdf"* ]] || return 1
    [[ "$output" != *"image.jpg"* ]] || return 1
    [[ "$output" != *"archive.tar.gz"* ]] || return 1
    [[ "$output" == *"Installer.dmg"* ]]
}

@test "scan_installers_in_path (fd): handles filenames with spaces" {
    if ! require_fd; then
        return 0
    fi

    touch "$HOME/Downloads/My App Installer.dmg"

    run /bin/bash -euo pipefail -c '
        export MOLE_TEST_MODE=1
        source "$1"
        scan_installers_in_path "$2"
    ' bash "$PROJECT_ROOT/bin/installer.sh" "$HOME/Downloads"

    [ "$status" -eq 0 ]
    [[ "$output" == *"My App Installer.dmg"* ]]
}

@test "scan_installers_in_path (fd): handles filenames with special characters" {
    if ! require_fd; then
        return 0
    fi

    touch "$HOME/Downloads/App-v1.2.3_beta.pkg"

    run /bin/bash -euo pipefail -c '
        export MOLE_TEST_MODE=1
        source "$1"
        scan_installers_in_path "$2"
    ' bash "$PROJECT_ROOT/bin/installer.sh" "$HOME/Downloads"

    [ "$status" -eq 0 ]
    [[ "$output" == *"App-v1.2.3_beta.pkg"* ]]
}

@test "scan_installers_in_path (fd): returns empty for directory with no installers" {
    if ! require_fd; then
        return 0
    fi

    # Create some non-installer files
    touch "$HOME/Downloads/document.pdf"
    touch "$HOME/Downloads/image.png"

    run /bin/bash -euo pipefail -c '
        export MOLE_TEST_MODE=1
        source "$1"
        scan_installers_in_path "$2"
    ' bash "$PROJECT_ROOT/bin/installer.sh" "$HOME/Downloads"

    [ "$status" -eq 0 ]
    [[ -z "$output" ]]
}

@test "scan_installers_in_path (fd): skips symlinks to regular files" {
    if ! require_fd; then
        return 0
    fi

    touch "$HOME/Downloads/real.dmg"
    ln -s "$HOME/Downloads/real.dmg" "$HOME/Downloads/symlink.dmg"
    ln -s /nonexistent "$HOME/Downloads/dangling.lnk"

    run /bin/bash -euo pipefail -c '
        export MOLE_TEST_MODE=1
        source "$1"
        scan_installers_in_path "$2"
    ' bash "$PROJECT_ROOT/bin/installer.sh" "$HOME/Downloads"

    [ "$status" -eq 0 ]
    [[ "$output" == *"real.dmg"* ]] || return 1
    [[ "$output" != *"symlink.dmg"* ]] || return 1
    [[ "$output" != *"dangling.lnk"* ]]
}
