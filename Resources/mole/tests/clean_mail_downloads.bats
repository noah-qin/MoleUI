#!/usr/bin/env bats

# Regression for #1344: a Mail Downloads directory that cannot be sized within
# the disk-verify timeout (exit 124) must be skipped as a single target, not
# end the whole `mo clean` run at User essentials. Signal-class statuses
# (>=128) keep their cancellation semantics.

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT

    ORIGINAL_HOME="${HOME:-}"
    export ORIGINAL_HOME

    HOME="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-mail-downloads.XXXXXX")"
    export HOME
}

teardown_file() {
    if [[ "$HOME" == "${BATS_TEST_DIRNAME}/tmp-mail-downloads."* ]]; then
        rm -rf "$HOME"
    fi
    if [[ -n "${ORIGINAL_HOME:-}" ]]; then
        export HOME="$ORIGINAL_HOME"
    fi
}

setup() {
    if [[ "$HOME" != "${BATS_TEST_DIRNAME}/tmp-mail-downloads."* ]]; then
        printf 'FATAL: HOME is not a test temp dir: %s\n' "$HOME" >&2
        return 1
    fi
    rm -rf "$HOME/Library"
}

@test "mail dir sizing timeout (124) skips the target and keeps the run going" {
    mkdir -p "$HOME/Library/Containers/com.apple.mail/Data/Library/Mail Downloads"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc << 'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/user.sh"
pgrep() { return 1; }
start_section_spinner() { :; }
stop_section_spinner() { :; }
note_activity() { :; }
get_path_size_kb() { return 124; }
_clean_mail_downloads
echo "RC=$?"
EOF

    [ "$status" -eq 0 ] || return 1
    [[ "$output" == *"Mail Downloads · skipped (sizing unavailable)"* ]] || return 1
    [[ "$output" == *"RC=0"* ]] || return 1
}

@test "mail dir sizing timeout (124) skips one dir and still cleans the other" {
    mkdir -p "$HOME/Library/Mail Downloads"
    echo x > "$HOME/Library/Mail Downloads/old.bin"
    touch -t 202401010000 "$HOME/Library/Mail Downloads/old.bin"
    mkdir -p "$HOME/Library/Containers/com.apple.mail/Data/Library/Mail Downloads"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc << 'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/user.sh"
pgrep() { return 1; }
start_section_spinner() { :; }
stop_section_spinner() { :; }
note_activity() { :; }
safe_remove() { echo "REMOVE:$1"; return 0; }
get_path_size_kb() {
    if [[ "$1" == "$HOME/Library/Containers/com.apple.mail/Data/Library/Mail Downloads" ]]; then
        return 124
    fi
    if [[ "$1" == "$HOME/Library/Mail Downloads" ]]; then
        echo "6000"
        return 0
    fi
    echo "6000"
}
_clean_mail_downloads
echo "RC=$?"
EOF

    [ "$status" -eq 0 ] || return 1
    [[ "$output" == *"REMOVE:$HOME/Library/Mail Downloads/old.bin"* ]] || return 1
    [[ "$output" == *"Mail Downloads · skipped (sizing unavailable)"* ]] || return 1
    [[ "$output" == *"RC=0"* ]] || return 1
}

@test "mail attachment sizing timeout (124) skips the file without aborting" {
    mkdir -p "$HOME/Library/Mail Downloads"
    echo x > "$HOME/Library/Mail Downloads/stuck.bin"
    touch -t 202401010000 "$HOME/Library/Mail Downloads/stuck.bin"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc << 'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/user.sh"
pgrep() { return 1; }
start_section_spinner() { :; }
stop_section_spinner() { :; }
note_activity() { :; }
debug_log() { echo "DEBUG:$*"; }
safe_remove() { echo "REMOVE:$1"; return 0; }
get_path_size_kb() {
    if [[ "$1" == "$HOME/Library/Mail Downloads" ]]; then
        echo "6000"
        return 0
    fi
    return 124
}
_clean_mail_downloads
echo "RC=$?"
EOF

    [ "$status" -eq 0 ] || return 1
    [[ "$output" == *"Mail attachment sizing failed"* ]] || return 1
    [[ "$output" != *"REMOVE:"* ]] || return 1
    [[ "$output" == *"RC=0"* ]] || return 1
}

@test "mail dir sizing signal (130) still cancels the run" {
    mkdir -p "$HOME/Library/Containers/com.apple.mail/Data/Library/Mail Downloads"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc << 'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/user.sh"
pgrep() { return 1; }
start_section_spinner() { :; }
stop_section_spinner() { :; }
note_activity() { :; }
get_path_size_kb() { return 130; }
_clean_mail_downloads
echo "RC=$?"
EOF

    [ "$status" -eq 130 ] || return 1
    [[ "$output" != *"skipped (sizing unavailable)"* ]] || return 1
}

@test "mo clean completes when the Mail Downloads du stalls (#1344)" {
    mkdir -p "$HOME/Library/Caches"
    mkdir -p "$HOME/Library/Containers/com.apple.mail/Data/Library/Mail Downloads"
    echo x > "$HOME/Library/Containers/com.apple.mail/Data/Library/Mail Downloads/old.docx"

    SHIM_DIR="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/mail-shim.XXXXXX")"
    cat > "$SHIM_DIR/du" << 'SHIM'
#!/bin/bash
for a in "$@"; do
    if [[ "$a" == *"Mail Downloads"* ]]; then
        /bin/sleep 60
        exit 124
    fi
done
exec /usr/bin/du "$@"
SHIM
    chmod +x "$SHIM_DIR/du"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" \
        PATH="$SHIM_DIR:$PATH" MOLE_TIMEOUT_DISK_VERIFY_SEC=2 \
        /bin/bash --noprofile --norc << 'EOF'
set -euo pipefail
source "$PROJECT_ROOT/bin/clean.sh"
# Stub every other section so the run reaches the summary quickly; only
# clean_user_essentials (which contains _clean_mail_downloads) stays real.
for fn in clean_finder_metadata clean_app_caches clean_browsers \
    run_cloud_and_office_cleanup clean_developer_tools \
    clean_user_gui_applications clean_virtualization_tools \
    clean_application_support_logs clean_orphaned_app_data \
    clean_orphaned_system_services clean_orphaned_container_stubs \
    show_user_launch_agent_hint_notice \
    clean_apple_silicon_caches clean_cached_device_firmware \
    clean_time_machine_failed_backups check_large_file_candidates \
    show_project_artifact_hint_notice; do
    eval "$fn() { return 0; }"
done
perform_cleanup
EOF

    rm -rf "$SHIM_DIR"

    [ "$status" -eq 0 ] || return 1
    [[ "$output" == *"Cleanup complete"* ]] || return 1
    [[ "$output" == *"Mail Downloads · skipped (sizing unavailable)"* ]] || return 1
}

@test "mail dir sizing hard failure (1) skips the target and keeps the run going (#1366)" {
    # On Intel with macOS 26 the protected Mail container refuses du
    # outright: rc=1 immediately, no timeout. That must skip exactly like
    # the 124 case instead of cancelling the whole run.
    mkdir -p "$HOME/Library/Containers/com.apple.mail/Data/Library/Mail Downloads"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc << 'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/user.sh"
pgrep() { return 1; }
start_section_spinner() { :; }
stop_section_spinner() { :; }
note_activity() { :; }
get_path_size_kb() { return 1; }
_clean_mail_downloads
echo "RC=$?"
EOF

    [ "$status" -eq 0 ] || return 1
    [[ "$output" == *"Mail Downloads · skipped (sizing unavailable)"* ]] || return 1
    [[ "$output" == *"RC=0"* ]] || return 1
}
