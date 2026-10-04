#!/usr/bin/env bats

load helpers/common

setup_file() {
    mole_test_setup_home installers-home

    if command -v fd > /dev/null 2>&1; then
        export FD_AVAILABLE=1
    else
        export FD_AVAILABLE=0
    fi
}

teardown_file() {
    mole_test_teardown_home
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

@test "installer discovery discards fd and find output when the producer fails" {
    touch "$HOME/Downloads/incomplete.dmg"
    # shellcheck disable=SC2016 # Expanded by the fake command at execution time.
    mole_test_fake_command fd 'printf "%s\0" "$HOME/Downloads/incomplete.dmg"; exit 74'
    # shellcheck disable=SC2016 # Expanded by the fake command at execution time.
    mole_test_fake_command find 'printf "%s\0" "$HOME/Downloads/incomplete.dmg"; exit 74'

    local backend
    for backend in fd find; do
        run /bin/bash --noprofile --norc -c '
            export MOLE_TEST_MODE=1
            source "$1"
            backend="$3"
            command() {
                if [[ "$backend" == find && "${1:-}" == -v && "${2:-}" == fd ]]; then return 1; fi
                builtin command "$@"
            }
            rc=0
            scan_installers_in_path "$HOME/Downloads" > "$2" || rc=$?
            [[ $rc -eq 74 ]] || exit 1
            [[ ! -s "$2" ]] || exit 1
            [[ -f "$HOME/Downloads/incomplete.dmg" ]] || exit 1
        ' bash "$PROJECT_ROOT/bin/installer.sh" "$BATS_TEST_TMPDIR/scan-output" "$backend"
        [ "$status" -eq 0 ] || return 1
    done
}

@test "failed installer discovery never reaches selection or reports an empty scan" {
    touch "$HOME/Downloads/incomplete.dmg"
    # shellcheck disable=SC2016 # Expanded by the fake command at execution time.
    mole_test_fake_command fd 'printf "%s\0" "$HOME/Downloads/incomplete.dmg"; exit 74'
    run /bin/bash --noprofile --norc -c '
        export MOLE_TEST_MODE=1
        source "$1"
        scan_all_installers() { scan_installers_in_path "$HOME/Downloads"; }
        show_installer_menu() { echo SELECTED; return 0; }
        rc=0
        main || rc=$?
        printf "RC=%s COUNT=%s\n" "$rc" "${#INSTALLER_PATHS[@]}"
        [[ -f "$HOME/Downloads/incomplete.dmg" ]] || exit 1
    ' bash "$PROJECT_ROOT/bin/installer.sh"
    [ "$status" -eq 0 ] || return 1
    [[ "$output" == *"RC=1 COUNT=0"* ]] || return 1
    [[ "$output" == *"Installer scan incomplete"* ]] || return 1
    [[ "$output" != *"SELECTED"* ]] || return 1
    [[ "$output" != *"No installer files to clean"* ]]
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
    # Match find's depth boundary and assert complete paths.
    [[ "$output" == *"/shallow.dmg"* ]] || return 1
    [[ "$output" == *"/level1/mid.dmg"* ]] || return 1
    [[ "$output" != *"/level1/level2/deep.dmg"* ]] || return 1
    [[ "$output" != *"/level1/level2/level3/too-deep.dmg"* ]]
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

@test "installer collection preserves exact filenames and deduplicates overlapping roots" {
    local fixture="$HOME/Downloads/first"$'\n'"second.dmg"
    touch "$fixture"
    local scan_path
    for scan_path in "$PATH" "/usr/bin:/bin"; do
        # shellcheck disable=SC2016 # The child shell evaluates this script.
        run env PATH="$scan_path" /bin/bash --noprofile --norc -c '
            export MOLE_TEST_MODE=1
            source "$1"
            scan_all_installers() {
                scan_installers_in_path "$HOME/Downloads" || return $?
                scan_installers_in_path "$HOME/Downloads"
            }
            collect_installers
            [[ ${#INSTALLER_PATHS[@]} -eq 1 ]] || exit 1
            [[ "${INSTALLER_PATHS[0]}" == "$2" ]] || exit 1
            [[ ! "${DISPLAY_NAMES[0]}" =~ [[:cntrl:]] ]] || exit 1
            build_installer_delete_plan 0
            [[ "${INSTALLER_DELETE_PATHS[0]}" == "$2" ]] || exit 1
        ' bash "$PROJECT_ROOT/bin/installer.sh" "$fixture"
        [ "$status" -eq 0 ] || return 1
    done
}

@test "installer collection discards output from failed sorting" {
    touch "$HOME/Downloads/valid.dmg"
    # shellcheck disable=SC2016 # Expanded by the fake command at execution time.
    mole_test_fake_command sort 'printf "%s\0" "$HOME/Downloads/valid.dmg"; exit 74'
    run /bin/bash --noprofile --norc -c '
        export MOLE_TEST_MODE=1
        source "$1"
        scan_all_installers() { scan_installers_in_path "$HOME/Downloads"; }
        rc=0
        collect_installers || rc=$?
        [[ $rc -eq $INSTALLER_EXIT_SCAN_FAILED ]] || exit 1
        [[ ${#INSTALLER_PATHS[@]} -eq 0 ]] || exit 1
    ' bash "$PROJECT_ROOT/bin/installer.sh"
    [ "$status" -eq 0 ]
}

@test "installer discovery times out a stalled producer without publishing its prefix" {
    touch "$HOME/Downloads/incomplete.dmg"
    # shellcheck disable=SC2016 # Expanded by the fake command at execution time.
    mole_test_fake_command fd 'printf "%s\0" "$HOME/Downloads/incomplete.dmg"; exec sleep 30'
    # shellcheck disable=SC2016 # The child shell evaluates this script.
    run env MOLE_TIMEOUT_DISK_VERIFY_SEC=2 /bin/bash --noprofile --norc -c '
        export MOLE_TEST_MODE=1
        source "$1"
        rc=0
        scan_installers_in_path "$HOME/Downloads" > "$2" || rc=$?
        mole_rc_timeout "$rc" || exit 1
        [[ ! -s "$2" ]] || exit 1
        [[ -f "$HOME/Downloads/incomplete.dmg" ]] || exit 1
        [[ $SECONDS -lt 6 ]] || exit 1
    ' bash "$PROJECT_ROOT/bin/installer.sh" "$BATS_TEST_TMPDIR/scan-output"
    [ "$status" -eq 0 ]
}

@test "expired installer scan budget does not start another directory producer" {
    export INSTALLER_TRACE="$BATS_TEST_TMPDIR/producer-started"
    # shellcheck disable=SC2016 # Expanded by the fake command at execution time.
    mole_test_fake_command fd 'touch "$INSTALLER_TRACE"; exit 0'
    run /bin/bash --noprofile --norc -c '
        export MOLE_TEST_MODE=1
        source "$1"
        scan_installers_in_path "$HOME/Downloads"
        [[ -f "$INSTALLER_TRACE" ]] || exit 1
        /bin/rm -f "$INSTALLER_TRACE"
        rc=0
        scan_installers_in_path "$HOME/Downloads" "$SECONDS" || rc=$?
        mole_rc_timeout "$rc" || exit 1
        [[ ! -e "$INSTALLER_TRACE" ]] || exit 1
    ' bash "$PROJECT_ROOT/bin/installer.sh"
    [ "$status" -eq 0 ]
}

@test "installer collection never publishes metadata from a vanished candidate" {
    touch "$HOME/Downloads/first.dmg"
    # shellcheck disable=SC2016 # Expanded by the fake command at execution time.
    mole_test_fake_command fd 'printf "%s\0" "$HOME/Downloads/first.dmg" "$HOME/Downloads/vanished.dmg"'
    run /bin/bash --noprofile --norc -c '
        export MOLE_TEST_MODE=1
        source "$1"
        scan_all_installers() { scan_installers_in_path "$HOME/Downloads" "$1"; }
        rc=0
        collect_installers || rc=$?
        [[ $rc -eq $INSTALLER_EXIT_SCAN_FAILED ]] || exit 1
        [[ ${#INSTALLER_PATHS[@]} -eq 0 && ${#INSTALLER_SIZES[@]} -eq 0 ]] || exit 1
        [[ ${#INSTALLER_SOURCES[@]} -eq 0 && ${#DISPLAY_NAMES[@]} -eq 0 ]] || exit 1
        [[ -f "$HOME/Downloads/first.dmg" ]] || exit 1
    ' bash "$PROJECT_ROOT/bin/installer.sh"
    [ "$status" -eq 0 ]
}

@test "installer interruption stops before later deletions" {
    touch "$HOME/Downloads/first.dmg" "$HOME/Downloads/second.dmg"
    local boundary
    for boundary in size delete; do
        local cancel_status
        for cancel_status in 130 124; do
            [[ "$boundary" != size || $cancel_status -eq 130 ]] || continue
            run /bin/bash --noprofile --norc -c '
                export MOLE_TEST_MODE=1
                source "$1"
                INSTALLER_PATHS=("$HOME/Downloads/first.dmg" "$HOME/Downloads/second.dmg")
                INSTALLER_SIZES=(0 0)
                build_installer_delete_plan 0 1
                interruption_trace="$3"
                cancel_status="$4"
                case "$2" in
                    size) installer_file_size_bytes() {
                        [[ "$1" == "$HOME/Downloads/first.dmg" ]] && return "$cancel_status"
                        printf "%s\n" "$1" >> "$interruption_trace"
                        get_file_size "$1"
                    } ;;
                    delete) mole_delete() {
                        [[ "$1" == "$HOME/Downloads/first.dmg" ]] && return "$cancel_status"
                        printf "%s\n" "$1" >> "$interruption_trace"
                        return 0
                    } ;;
                esac
                rc=0
                execute_installer_delete_plan || rc=$?
                [[ $rc -eq $cancel_status && $total_delete_failed -eq 1 ]] || exit 1
                [[ ! -e "$interruption_trace" ]] || exit 1
                [[ -f "$HOME/Downloads/first.dmg" && -f "$HOME/Downloads/second.dmg" ]] || exit 1
            ' bash "$PROJECT_ROOT/bin/installer.sh" "$boundary" "$BATS_TEST_TMPDIR/$boundary-$cancel_status-trace" "$cancel_status"
            [ "$status" -eq 0 ] || return 1
        done
    done
}

@test "installer confirmation and failure summary render filenames literally" {
    local fixture="$HOME/Downloads/real"$'\e'"[2Jspoof\\n.dmg"
    touch "$fixture"
    # shellcheck disable=SC2016 # The child shell evaluates this script.
    run /bin/bash --noprofile --norc -c '
        export MOLE_TEST_MODE=1
        source "$1"
        INSTALLER_PATHS=("$2")
        INSTALLER_SIZES=(0)
        MOLE_SELECTION_RESULT=0
        rc=0
        delete_selected_installers <<< q > "$3" || rc=$?
        [[ $rc -eq 1 && -f "$2" ]] || exit 1
        record_installer_delete_failure "$2" "delete failed"
        show_summary >> "$3"
        output=$(cat "$3")
        [[ "$output" != *$'"'"'\e'"'"'"[2Jspoof"* ]] || exit 1
        [[ "$output" == *"spoof"* && "$output" == *"\\\\n.dmg"* ]] || exit 1
    ' bash "$PROJECT_ROOT/bin/installer.sh" "$fixture" "$BATS_TEST_TMPDIR/rendered-output"
    [ "$status" -eq 0 ]
}

@test "installer command preserves producer cancellation and never opens selection" {
    mole_test_fake_command fd 'kill -TERM "$$"'
    run /bin/bash --noprofile --norc -c '
        export MOLE_TEST_MODE=1
        source "$1"
        scan_all_installers() { scan_installers_in_path "$HOME/Downloads" "$1"; }
        show_installer_menu() { echo SELECTED; return 0; }
        rc=0
        main || rc=$?
        printf "RC=%s COUNT=%s\n" "$rc" "${#INSTALLER_PATHS[@]}"
    ' bash "$PROJECT_ROOT/bin/installer.sh"
    [ "$status" -eq 0 ] || return 1
    [[ "$output" == *"RC=143 COUNT=0"* && "$output" == *"Installer scan interrupted"* ]] || return 1
    [[ "$output" != *"SELECTED"* ]]
}

@test "an unreadable subfolder keeps the readable installers with fd and find" {
    mkdir -p "$HOME/Downloads/denied"
    touch "$HOME/Downloads/visible.dmg" "$HOME/Downloads/denied/hidden.dmg"
    chmod 000 "$HOME/Downloads/denied"
    local backend
    for backend in fd find; do
        if [[ "$backend" == fd ]] && ! require_fd; then
            continue
        fi
        local scan_path="$PATH"
        [[ "$backend" == find ]] && scan_path="/usr/bin:/bin"
        # shellcheck disable=SC2016 # The child shell evaluates this script.
        run env PATH="$scan_path" /bin/bash --noprofile --norc -c '
            export MOLE_TEST_MODE=1
            source "$1"
            rc=0
            scan_installers_in_path "$HOME/Downloads" > "$2" || rc=$?
            [[ $rc -eq 0 ]] || { echo "rc=$rc"; exit 1; }
            seen_visible=0
            while IFS= read -r -d "" file; do
                [[ "$file" == "$HOME/Downloads/visible.dmg" ]] && seen_visible=1
                [[ "$file" == "$HOME/Downloads/denied/hidden.dmg" ]] && exit 1
            done < "$2"
            [[ $seen_visible -eq 1 ]] || exit 1
        ' bash "$PROJECT_ROOT/bin/installer.sh" "$BATS_TEST_TMPDIR/scan-output-$backend"
        [ "$status" -eq 0 ] || { chmod 700 "$HOME/Downloads/denied"; echo "$backend: $output"; return 1; }
    done
    chmod 700 "$HOME/Downloads/denied"
}

@test "a traversal diagnostic other than a permission refusal still rejects the scan" {
    touch "$HOME/Downloads/visible.dmg"
    # shellcheck disable=SC2016 # Expanded by the fake command at execution time.
    mole_test_fake_command fd 'printf "%s\0" "$HOME/Downloads/visible.dmg"; echo "[fd error]: $HOME/Downloads/disk: Input/output error (os error 5)" >&2; exit 0'
    # shellcheck disable=SC2016 # The child shell evaluates this script.
    run /bin/bash --noprofile --norc -c '
        export MOLE_TEST_MODE=1
        source "$1"
        rc=0
        scan_installers_in_path "$HOME/Downloads" > "$2" || rc=$?
        [[ $rc -eq $INSTALLER_EXIT_SCAN_FAILED && ! -s "$2" ]] || exit 1
        [[ "$INSTALLER_SCAN_FAILURE_PATH" == "$HOME/Downloads" ]] || exit 1
    ' bash "$PROJECT_ROOT/bin/installer.sh" "$BATS_TEST_TMPDIR/scan-output"
    [ "$status" -eq 0 ]
}

@test "debug traces do not turn healthy installer discovery into a failed scan" {
    touch "$HOME/Downloads/healthy.dmg"
    local backend
    for backend in fd find; do
        # shellcheck disable=SC2016 # The child shell evaluates this script.
        run env MO_DEBUG=1 /bin/bash --noprofile --norc -c '
            export MOLE_TEST_MODE=1
            source "$1"
            backend="$2"
            command() {
                if [[ "$backend" == find && "${1:-}" == -v && "${2:-}" == fd ]]; then return 1; fi
                builtin command "$@"
            }
            scan_all_installers() { scan_installers_in_path "$HOME/Downloads" "$1"; }
            collect_installers
            [[ ${#INSTALLER_PATHS[@]} -eq 1 ]] || exit 1
            [[ "${INSTALLER_PATHS[0]}" == "$HOME/Downloads/healthy.dmg" ]] || exit 1
        ' bash "$PROJECT_ROOT/bin/installer.sh" "$backend"
        [ "$status" -eq 0 ] || return 1
        [[ "$output" == *"[TIMEOUT]"* ]] || return 1
    done
}

@test "installer backends follow the scan root but never descendant symlinks" {
    local fixture_root="$BATS_TEST_TMPDIR/scan-roots"
    mkdir -p "$fixture_root/real" "$fixture_root/outside"
    touch "$fixture_root/real/expected.dmg" "$fixture_root/outside/excluded.dmg"
    ln -s "$fixture_root/real" "$fixture_root/linked-root"
    ln -s "$fixture_root/outside" "$fixture_root/real/linked-child"
    ln -s "$fixture_root/outside/excluded.dmg" "$fixture_root/real/linked-file.dmg"
    local backend
    for backend in fd find; do
        # shellcheck disable=SC2016 # The child shell evaluates this script.
        run /bin/bash --noprofile --norc -c '
            export MOLE_TEST_MODE=1
            source "$1"
            backend="$2"
            command() {
                if [[ "$backend" == find && "${1:-}" == -v && "${2:-}" == fd ]]; then return 1; fi
                builtin command "$@"
            }
            root="$3"
            scan_all_installers() { scan_installers_in_path "$root" "$1"; }
            collect_installers
            [[ ${#INSTALLER_PATHS[@]} -eq 1 ]] || exit 1
            [[ "${INSTALLER_PATHS[0]}" == "$root/expected.dmg" ]] || exit 1
        ' bash "$PROJECT_ROOT/bin/installer.sh" "$backend" "$fixture_root/linked-root"
        [ "$status" -eq 0 ] || return 1
    done
}

@test "interrupted installer plan cannot confirm or probe later selections" {
    local fixture_root="$BATS_TEST_TMPDIR/plan-cancellation"
    mkdir -p "$fixture_root"
    touch "$fixture_root/first.dmg" "$fixture_root/second.dmg"
    local cancel_status
    for cancel_status in 124 130; do
        run /bin/bash --noprofile --norc -c '
            export MOLE_TEST_MODE=1
            source "$1"
            root="$2"
            cancel_status="$3"
            trace="$root/$cancel_status.trace"
            INSTALLER_PATHS=("$root/first.dmg" "$root/second.dmg")
            INSTALLER_SIZES=(0 0)
            MOLE_SELECTION_RESULT=0,1
            mole_deletion_identity() {
                [[ "$1" != "$root/first.dmg" ]] || return "$cancel_status"
                printf "%s\n" "$1" >> "$trace"
                "$STAT_BSD" -f%d:%i:%m "$1"
            }
            rc=0
            delete_selected_installers </dev/null || rc=$?
            [[ $rc -eq $cancel_status && ${#INSTALLER_DELETE_PATHS[@]} -eq 0 ]] || exit 1
            [[ ! -e "$trace" && -f "$root/first.dmg" && -f "$root/second.dmg" ]] || exit 1
        ' bash "$PROJECT_ROOT/bin/installer.sh" "$fixture_root" "$cancel_status"
        [ "$status" -eq 0 ] || return 1
        [[ "$output" != *"Files to be removed"* ]] || return 1
    done
}
