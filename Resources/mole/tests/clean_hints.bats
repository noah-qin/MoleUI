#!/usr/bin/env bats

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT

    ORIGINAL_HOME="${HOME:-}"
    export ORIGINAL_HOME

    HOME="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-clean-hints-home.XXXXXX")"
    export HOME
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
    rm -rf "${HOME:?}"/*
    rm -rf "${HOME:?}"/.[!.]* "${HOME:?}"/..?* 2> /dev/null || true
    mkdir -p "$HOME/.config/mole"
}

teardown() {
    rm -rf "$HOME/Library/LaunchAgents"
}

@test "probe_project_artifact_hints reuses purge targets and excludes noisy names" {
    local root="$HOME/hints-root"
    mkdir -p "$root/proj/node_modules" "$root/proj/vendor" "$root/proj/bin"
    touch "$root/proj/package.json"
    printf '%s\n' "$root" > "$HOME/.config/mole/purge_paths"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc << 'EOT1'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/hints.sh"
run_with_timeout() { shift; "$@"; }
probe_project_artifact_hints
printf 'count=%s\n' "$PROJECT_ARTIFACT_HINT_COUNT"
printf 'examples=%s\n' "${PROJECT_ARTIFACT_HINT_EXAMPLES[*]}"
EOT1

    [ "$status" -eq 0 ]
    [[ "$output" == *"count=1"* ]] || return 1
    [[ "$output" == *"node_modules"* ]] || return 1
    [[ "$output" != *"vendor"* ]] || return 1
    [[ "$output" != *"/bin"* ]]
}

@test "show_project_artifact_hint_notice renders sampled summary" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc << 'EOT2'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/hints.sh"
probe_project_artifact_hints() {
    PROJECT_ARTIFACT_HINT_DETECTED=true
    PROJECT_ARTIFACT_HINT_COUNT=5
    PROJECT_ARTIFACT_HINT_TRUNCATED=true
    PROJECT_ARTIFACT_HINT_EXAMPLES=("~/www/demo/node_modules" "~/www/demo/target")
    PROJECT_ARTIFACT_HINT_ESTIMATED_KB=2048
    PROJECT_ARTIFACT_HINT_ESTIMATE_SAMPLES=2
    PROJECT_ARTIFACT_HINT_ESTIMATE_PARTIAL=false
}
bytes_to_human() { echo "2.00MB"; }
note_activity() { :; }
show_project_artifact_hint_notice
EOT2

    [ "$status" -eq 0 ]
    [[ "$output" == *"Build artifacts"* ]] || return 1
    [[ "$output" == *"5+ dirs, 2.00MB+"* ]] || return 1
    [[ "$output" == *"mo purge"* ]] || return 1
}

@test "show_project_artifact_hint_notice points zero-size samples to include-empty (#869)" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc << 'EOT2B'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/hints.sh"
probe_project_artifact_hints() {
    PROJECT_ARTIFACT_HINT_DETECTED=true
    PROJECT_ARTIFACT_HINT_COUNT=1
    PROJECT_ARTIFACT_HINT_TRUNCATED=false
    PROJECT_ARTIFACT_HINT_EXAMPLES=("~/www/demo/node_modules")
    PROJECT_ARTIFACT_HINT_ESTIMATED_KB=0
    PROJECT_ARTIFACT_HINT_ESTIMATE_SAMPLES=1
    PROJECT_ARTIFACT_HINT_ESTIMATE_PARTIAL=false
}
bytes_to_human() { echo "0B"; }
note_activity() { :; }
show_project_artifact_hint_notice
EOT2B

    [ "$status" -eq 0 ]
    [[ "$output" == *", 0B"* ]] || return 1
    [[ "$output" == *"mo purge --include-empty"* ]] || return 1
}

@test "show_project_artifact_hint_notice reports skipped slow project artifact scans (#1053)" {
    local root="$HOME/Library/CloudStorage"
    mkdir -p "$root"
    printf '%s\n' "$root" > "$HOME/.config/mole/purge_paths"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc << 'EOT2C'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/hints.sh"
run_with_timeout() {
    shift
    return 124
}
note_activity() { :; }
show_project_artifact_hint_notice
EOT2C

    [ "$status" -eq 0 ]
    [[ "$output" == *"Build artifacts · scan skipped"* ]] || return 1
    [[ "$output" == *"mo purge"* ]] || return 1
}

@test "probe_project_artifact_hints stops at the wall-clock budget (#1053)" {
    local root="$HOME/hints-root"
    mkdir -p "$root/proj/node_modules"
    touch "$root/proj/package.json"
    printf '%s\n' "$root" > "$HOME/.config/mole/purge_paths"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" MOLE_TIMEOUT_HINT_SCAN_SEC=0 \
        /bin/bash --noprofile --norc << 'EOT2D'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/hints.sh"
run_with_timeout() { shift; "$@"; }
probe_project_artifact_hints
printf 'count=%s\n' "$PROJECT_ARTIFACT_HINT_COUNT"
printf 'skipped=%s\n' "$PROJECT_ARTIFACT_HINT_SCAN_SKIPPED"
EOT2D

    [ "$status" -eq 0 ]
    [[ "$output" == *"count=0"* ]] || return 1
    [[ "$output" == *"skipped=true"* ]]
}

@test "probe_project_artifact_hints respects budget inside nested-dir loop (#1053)" {
    # Regression: old code had no deadline check inside the nested-dir while loop.
    # When a single scan root is used the outer-root deadline guard never fires for
    # the second time (the loop ends before the next iteration), so the nested loop
    # could run unchecked after SECONDS crossed the deadline.
    #
    # Setup: one root with one project containing two nested sub-projects, each
    # with a build/ artifact.  hint_collect_child_dirs_with_timeout sleeps 2s on
    # the nested call so SECONDS advances past the 1s budget before the nested-dir
    # while loop starts.
    #
    # New code: deadline fires on the FIRST nested-dir iteration → count=0, skipped=true.
    # Old code: nested loop runs without a deadline check → count=2, skipped=false.
    local root="$HOME/hints-deadline-nested"
    mkdir -p "$root/bigproject/sub1/build"
    mkdir -p "$root/bigproject/sub2/build"
    touch "$root/bigproject/package.json"
    printf '%s\n' "$root" > "$HOME/.config/mole/purge_paths"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" \
        MOLE_TIMEOUT_HINT_SCAN_SEC=1 \
        HINTS_ROOT="$root" \
        /bin/bash --noprofile --norc << 'EOT_NESTED'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/hints.sh"
run_with_timeout() { shift; "$@"; }
hint_collect_child_dirs_with_timeout() {
    local dir="$1" out="$2"
    if [[ "$dir" == "$HINTS_ROOT" ]]; then
        printf '%s\0' "$HINTS_ROOT/bigproject" >> "$out"
    else
        # Simulate a slow nested find that lets SECONDS cross the 1s budget.
        sleep 2
        printf '%s\0' "$HINTS_ROOT/bigproject/sub1" "$HINTS_ROOT/bigproject/sub2" >> "$out"
    fi
}
probe_project_artifact_hints
printf 'count=%s\n' "$PROJECT_ARTIFACT_HINT_COUNT"
printf 'skipped=%s\n' "$PROJECT_ARTIFACT_HINT_SCAN_SKIPPED"
EOT_NESTED

    [ "$status" -eq 0 ]
    [[ "$output" == *"count=0"* ]] || return 1
    [[ "$output" == *"skipped=true"* ]]
}

@test "show_user_launch_agent_hint_notice reports missing app-backed target" {
    mkdir -p "$HOME/Library/LaunchAgents"
    cat > "$HOME/Library/LaunchAgents/com.example.stale.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.example.stale</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Applications/Missing.app/Contents/MacOS/Missing</string>
    </array>
</dict>
</plist>
PLIST

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc << 'EOT4'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/hints.sh"
note_activity() { :; }
show_user_launch_agent_hint_notice
EOT4

    [ "$status" -eq 0 ]
    [[ "$output" == *"Stale login item · ~/Library/LaunchAgents/com.example.stale.plist"* ]] || return 1
    [[ "$output" == *"Missing app/helper target"* ]] || return 1
    [[ "$output" == *"review before removing"* ]] || return 1
}

@test "show_user_launch_agent_hint_notice trusts an existing executable Program target (#1262)" {
    local updater="$HOME/Library/Application Support/Google/GoogleUpdater/GoogleUpdater.app/Contents/MacOS/GoogleUpdater"
    mkdir -p "$HOME/Library/LaunchAgents" "$(dirname "$updater")"
    touch "$updater"
    chmod +x "$updater"
    cat > "$HOME/Library/LaunchAgents/com.google.GoogleUpdater.wake.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.google.GoogleUpdater.wake</string>
    <key>ProgramArguments</key>
    <array>
        <string>$updater</string>
        <string>--wake</string>
    </array>
    <key>AssociatedBundleIdentifiers</key>
    <array>
        <string>com.google.GoogleUpdater</string>
    </array>
</dict>
</plist>
PLIST

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" UPDATER="$updater" /bin/bash --noprofile --norc << 'EOT4A'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/hints.sh"
bundle_has_installed_app() { return 0; }
note_activity() { :; }

live_output=$(show_user_launch_agent_hint_notice)
[[ "$live_output" != *"Stale login item"* ]] || exit 1

chmod -x "$UPDATER"
show_user_launch_agent_hint_notice

chmod +x "$UPDATER"
command rm -f -- "$UPDATER"
show_user_launch_agent_hint_notice
EOT4A

    [ "$status" -eq 0 ]
    [[ "$output" == *"Stale login item · ~/Library/LaunchAgents/com.google.GoogleUpdater.wake.plist"* ]] || return 1
    [[ "$output" == *"Program target is not executable"* ]] || return 1
    [[ "$output" == *"Missing app/helper target"* ]] || return 1
}

@test "show_user_launch_agent_hint_notice gives Program precedence over ProgramArguments.0" {
    mkdir -p "$HOME/Library/LaunchAgents"
    cat > "$HOME/Library/LaunchAgents/com.example.program-precedence.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.example.program-precedence</string>
    <key>Program</key>
    <string>/Applications/Missing.app/Contents/MacOS/Missing</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>--version</string>
    </array>
</dict>
</plist>
PLIST

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc << 'EOT4B'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/hints.sh"
note_activity() { :; }
show_user_launch_agent_hint_notice
EOT4B

    [ "$status" -eq 0 ]
    [[ "$output" == *"Stale login item · ~/Library/LaunchAgents/com.example.program-precedence.plist"* ]] || return 1
    [[ "$output" == *"Missing app/helper target"* ]] || return 1
}

@test "show_user_launch_agent_hint_notice skips custom shell wrappers" {
    mkdir -p "$HOME/Library/LaunchAgents"
    cat > "$HOME/Library/LaunchAgents/com.example.custom.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.example.custom</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>-c</string>
        <string>$HOME/bin/custom-task</string>
    </array>
</dict>
</plist>
PLIST

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc << 'EOT5'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/hints.sh"
note_activity() { :; }
run_with_timeout() { shift; "$@"; }
show_user_launch_agent_hint_notice
EOT5

    [ "$status" -eq 0 ]
    [[ "$output" != *"Stale login item"* ]] || return 1
}

@test "show_user_launch_agent_hint_notice skips MachServices-only plists" {
    mkdir -p "$HOME/Library/LaunchAgents"
    cat > "$HOME/Library/LaunchAgents/com.google.keystone.agent.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.google.keystone.agent</string>
    <key>MachServices</key>
    <dict>
        <key>com.google.Keystone.Agent</key>
        <true/>
    </dict>
</dict>
</plist>
PLIST

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc << 'EOT6'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/hints.sh"
note_activity() { :; }
show_user_launch_agent_hint_notice
EOT6

    [ "$status" -eq 0 ]
    [[ "$output" != *"Stale login item"* ]] || return 1
    [[ "$output" != *"Associated app not found"* ]] || return 1
}

@test "project artifact hint shows a loading state while probing" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc << 'EOT7'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/hints.sh"
note_activity() { :; }
start_section_spinner() { echo "SPIN:$1"; }
stop_section_spinner() { echo "SPIN-STOP"; }
# The probe itself can take up to its 15s budget; the section must show a
# loading state for that whole window, not pop the row out of silence.
probe_project_artifact_hints() {
    echo "PROBE"
    PROJECT_ARTIFACT_HINT_DETECTED=false
    PROJECT_ARTIFACT_HINT_SCAN_SKIPPED=false
}
show_project_artifact_hint_notice
EOT7

    [ "$status" -eq 0 ]
    [[ "$output" == *"SPIN:Scanning project artifacts..."* ]] || return 1
    # Spinner starts before the probe runs and stops after it.
    [[ "$output" == *"SPIN:Scanning project artifacts...
PROBE
SPIN-STOP"* ]]
}
