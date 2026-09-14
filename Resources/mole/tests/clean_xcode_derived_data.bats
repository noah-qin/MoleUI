#!/usr/bin/env bats

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT

    ORIGINAL_HOME="${HOME:-}"
    export ORIGINAL_HOME

    HOME="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-xcode-dd.XXXXXX")"
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

@test "clean_xcode_derived_data reports project count and size" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc << 'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/app_caches.sh"

start_section_spinner() { :; }
stop_section_spinner() { :; }
note_activity() { :; }
is_path_whitelisted() { return 1; }
cleanup_result_color_kb() { echo "\033[0;32m"; }
bytes_to_human() { echo "36 KB"; }
DRY_RUN=false
files_cleaned=0
total_size_cleaned=0
total_items=0

pgrep() { return 1; }
export -f pgrep

dd_dir="$HOME/Library/Developer/Xcode/DerivedData"
mkdir -p "$dd_dir/ProjectAlpha-abcdef123"
mkdir -p "$dd_dir/ProjectBeta-ghijkl456"
mkdir -p "$dd_dir/ProjectGamma-mnopqr789"
echo "build output" > "$dd_dir/ProjectAlpha-abcdef123/build.o"
echo "build output" > "$dd_dir/ProjectBeta-ghijkl456/build.o"
echo "build output" > "$dd_dir/ProjectGamma-mnopqr789/build.o"

clean_xcode_derived_data
printf 'COUNTERS:%s:%s:%s\n' "$files_cleaned" "$total_size_cleaned" "$total_items"
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"3 projects"* ]] || return 1
    [[ "$output" == *"Xcode DerivedData"* ]] || return 1
    [[ "$output" == *"COUNTERS:3:"*":1"* ]]
}

@test "clean_xcode_derived_data honors a real DerivedData whitelist entry (#710)" {
    # Uses the real is_path_whitelisted (not a stub) with an actual whitelist
    # pattern. clean_xcode_derived_data deletes via safe_remove directly, so
    # the protection has to live in safe_remove; before that fix this test
    # deletes the build dirs and fails.
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc << 'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/app_caches.sh"

start_section_spinner() { :; }
stop_section_spinner() { :; }
note_activity() { :; }
cleanup_result_color_kb() { echo "\033[0;32m"; }
bytes_to_human() { echo "36 KB"; }
DRY_RUN=false
files_cleaned=0
total_size_cleaned=0
total_items=0

pgrep() { return 1; }
export -f pgrep

dd_dir="$HOME/Library/Developer/Xcode/DerivedData"
mkdir -p "$dd_dir/ProjectAlpha-abcdef123"
echo "build output" > "$dd_dir/ProjectAlpha-abcdef123/build.o"

# The shipped whitelist preset for DerivedData.
WHITELIST_PATTERNS=("$dd_dir/*")

clean_xcode_derived_data

[[ -f "$dd_dir/ProjectAlpha-abcdef123/build.o" ]] || { echo "WRONG: whitelisted DerivedData was deleted"; exit 1; }

# HOME is shared across tests in this file (setup_file, no per-test reset).
# The whitelisted dir survives by design, so remove it here or it leaks into
# the "empty DerivedData" test.
rm -rf "$dd_dir"
EOF

    [ "$status" -eq 0 ] || return 1
}

@test "clean_xcode_derived_data skips when xcodebuild is running" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc << 'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/app_caches.sh"

start_section_spinner() { :; }
stop_section_spinner() { :; }
note_activity() { :; }
is_path_whitelisted() { return 1; }
defer_cleanup_family() { echo "DEFER:$1"; }
DRY_RUN=false

pgrep() { [[ "$1" == "-x" && "$2" == "xcodebuild" ]]; }
export -f pgrep

dd_dir="$HOME/Library/Developer/Xcode/DerivedData"
mkdir -p "$dd_dir/SomeProject-abc123"
echo "data" > "$dd_dir/SomeProject-abc123/build.o"

clean_xcode_derived_data
[[ -f "$dd_dir/SomeProject-abc123/build.o" ]] || exit 1
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"DEFER:Xcode"* ]] || return 1
    [[ "$output" != *"Xcode DerivedData · skipped"* ]]
}

@test "clean_xcode_derived_data keeps build output when pgrep fails" {
    run env HOME="$HOME/probe-error" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc << 'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/app_caches.sh"
note_activity() { :; }
pgrep() { return 2; }
safe_remove() { echo "UNEXPECTED_REMOVE:$1"; return 0; }

dd_dir="$HOME/Library/Developer/Xcode/DerivedData"
mkdir -p "$dd_dir/OwnedProject"
touch "$dd_dir/OwnedProject/build.o"
clean_xcode_derived_data
[[ -f "$dd_dir/OwnedProject/build.o" ]] || exit 1
EOF

    [ "$status" -eq 0 ] || {
        echo "$output"
        return 1
    }
    [[ "$output" == *"skipped (process state unknown)"* ]] || return 1
    [[ "$output" != *"UNEXPECTED_REMOVE"* ]]
}

@test "clean_xcode_derived_data keeps build output when pgrep is unavailable" {
    run env HOME="$HOME/probe-missing" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc << 'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/app_caches.sh"
note_activity() { :; }

dd_dir="$HOME/Library/Developer/Xcode/DerivedData"
mkdir -p "$dd_dir/OwnedProject"
touch "$dd_dir/OwnedProject/build.o"
PATH=/nonexistent
clean_xcode_derived_data
[[ -f "$dd_dir/OwnedProject/build.o" ]] || exit 1
EOF

    [ "$status" -eq 0 ] || {
        echo "$output"
        return 1
    }
    [[ "$output" == *"skipped (process state unknown)"* ]]
}

@test "clean_xcode_derived_data reports completed removals before a tooling race stops it" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc << 'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/app_caches.sh"

start_section_spinner() { :; }
stop_section_spinner() { :; }
note_activity() { :; }
is_path_whitelisted() { return 1; }
cleanup_result_color_kb() { echo ""; }
bytes_to_human() { echo "$1 bytes"; }
get_path_size_kb() { echo 1; }
safe_remove() { command rm -rf "$1"; }
DRY_RUN=false
files_cleaned=0
total_size_cleaned=0
total_items=0

probe_round=0
_xcode_cleanup_process_state() {
    probe_round=$((probe_round + 1))
    if [[ $probe_round -le 3 ]]; then
        return 1
    fi
    return 0
}

dd_dir="$HOME/Library/Developer/Xcode/DerivedData"
rm -rf "$dd_dir"
mkdir -p "$dd_dir/One" "$dd_dir/Two" "$dd_dir/Three"

clean_xcode_derived_data

remaining=$(command find "$dd_dir" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
[[ "$remaining" -eq 2 ]] || { echo "WRONG_REMAINING:$remaining"; exit 1; }
[[ "$files_cleaned" -eq 1 && "$total_items" -eq 1 && "$total_size_cleaned" -eq 1 ]] || {
    echo "WRONG_COUNTERS:$files_cleaned:$total_items:$total_size_cleaned"
    exit 1
}
rm -rf "$dd_dir"
EOF

    [ "$status" -eq 0 ] || {
        echo "$output"
        return 1
    }
    [[ "$output" == *"Xcode DerivedData · 1 project"* ]] || return 1
    [[ "$output" != *"Xcode DerivedData · stopped"* ]]
}

@test "clean_xcode_derived_data rechecks tooling after the size probe" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc << 'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/app_caches.sh"
note_activity() { :; }
is_path_whitelisted() { return 1; }
get_path_size_kb() { touch "$HOME/xcode-started"; echo 1; }
safe_remove() { echo "UNEXPECTED_REMOVE:$1"; }
_xcode_cleanup_process_state() {
    [[ -e "$HOME/xcode-started" ]] && return 0
    return 1
}
DRY_RUN=false
files_cleaned=0
total_size_cleaned=0
total_items=0

dd_dir="$HOME/Library/Developer/Xcode/DerivedData"
rm -rf "$dd_dir" "$HOME/xcode-started"
mkdir -p "$dd_dir/One"
clean_xcode_derived_data
[[ -d "$dd_dir/One" ]] || { echo "WRONG: project removed"; exit 1; }
rm -rf "$dd_dir" "$HOME/xcode-started"
EOF

    [ "$status" -eq 0 ] || {
        echo "$output"
        return 1
    }
    [[ "$output" != *"Xcode DerivedData · stopped"* ]] || return 1
    [[ "$output" != *"UNEXPECTED_REMOVE"* ]]
}

@test "clean_xcode_derived_data passes its measured size to the real deletion sink" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc << 'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/app_caches.sh"
note_activity() { :; }
is_path_whitelisted() { return 1; }
cleanup_result_color_kb() { echo ""; }
bytes_to_human() { echo "$1 bytes"; }
get_path_size_kb() {
    printf 'size\n' >> "$HOME/derived-size-probes"
    local round
    round=$(wc -l < "$HOME/derived-size-probes" | tr -d ' ')
    [[ $round -ge 2 ]] && touch "$HOME/xcode-started"
    echo 1
}
_xcode_cleanup_process_state() {
    [[ -e "$HOME/xcode-started" ]] && return 0
    return 1
}
DRY_RUN=false
files_cleaned=0
total_size_cleaned=0
total_items=0

dd_dir="$HOME/Library/Developer/Xcode/DerivedData"
rm -rf "$dd_dir" "$HOME/xcode-started" "$HOME/derived-size-probes"
mkdir -p "$dd_dir/One"
clean_xcode_derived_data
[[ ! -e "$dd_dir/One" ]] || { echo "WRONG: project remains"; exit 1; }
[[ ! -e "$HOME/xcode-started" ]] || { echo "WRONG: deletion sink repeated size probe"; exit 1; }
[[ "$(wc -l < "$HOME/derived-size-probes" | tr -d ' ')" -eq 1 ]] || exit 1
rm -rf "$dd_dir" "$HOME/derived-size-probes"
EOF

    [ "$status" -eq 0 ] || {
        echo "$output"
        return 1
    }
}

@test "clean_xcode_derived_data handles empty DerivedData" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc << 'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/app_caches.sh"

start_section_spinner() { :; }
stop_section_spinner() { :; }
note_activity() { :; }
is_path_whitelisted() { return 1; }
defer_cleanup_family() { echo "UNEXPECTED_DEFER:$1"; }
DRY_RUN=false
pgrep() { return 0; }
export -f pgrep

mkdir -p "$HOME/Library/Developer/Xcode/DerivedData"

clean_xcode_derived_data
EOF

    [ "$status" -eq 0 ]
    [[ "$output" != *"projects"* ]]
    [[ "$output" != *"UNEXPECTED_DEFER"* ]]
}

@test "clean_xcode_derived_data handles missing DerivedData dir" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc << 'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/app_caches.sh"

start_section_spinner() { :; }
stop_section_spinner() { :; }
note_activity() { :; }
is_path_whitelisted() { return 1; }
DRY_RUN=false
pgrep() { return 1; }
export -f pgrep

clean_xcode_derived_data
EOF

    [ "$status" -eq 0 ]
}

@test "clean_xcode_derived_data dry run shows would-clean message" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc << 'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/app_caches.sh"

start_section_spinner() { :; }
stop_section_spinner() { :; }
note_activity() { :; }
is_path_whitelisted() { return 1; }
DRY_RUN=true
pgrep() { return 1; }
export -f pgrep

dd_dir="$HOME/Library/Developer/Xcode/DerivedData"
mkdir -p "$dd_dir/MyApp-abc123"
echo "data" > "$dd_dir/MyApp-abc123/build.o"

clean_xcode_derived_data
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"1 project"* ]]
}

@test "clean_xcode_derived_data dry run sizes only eligible projects" {
    run env HOME="$HOME/dry-run-filtered" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc << 'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/app_caches.sh"

note_activity() { :; }
DRY_RUN=true
pgrep() { return 1; }
bytes_to_human() { echo "$1 bytes"; }
get_path_size_kb() {
    [[ "$1" == *"/Eligible" ]] && echo 7 || echo 900
}

dd_dir="$HOME/Library/Developer/Xcode/DerivedData"
eligible="$dd_dir/Eligible"
excluded="$dd_dir/Excluded"
mkdir -p "$eligible" "$excluded"
touch "$eligible/build.o" "$excluded/private.o"
should_protect_path() { return 1; }
is_path_whitelisted() { [[ "$1" == "$excluded" ]]; }

clean_xcode_derived_data
EOF

    [ "$status" -eq 0 ] || {
        echo "$output"
        return 1
    }
    [[ "$output" == *"Xcode DerivedData · 1 project, 7168 bytes"* ]] || return 1
    [[ "$output" != *"928768 bytes"* ]]
}

@test "clean_xcode_derived_data dry run hides projects rejected after sizing" {
    run env HOME="$HOME/dry-run-policy-race" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc << 'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/app_caches.sh"

note_activity() { echo "UNEXPECTED_ACTIVITY"; }
DRY_RUN=true
pgrep() { return 1; }
get_path_size_kb() {
    mkdir -p "$1/com.apple.e5rt.e5bundlecache"
    echo 7
}
record_dry_run_cleanup_target() {
    holds_compiled_model_cache "$1" && return 1
    echo "UNEXPECTED_REGISTER:$1"
    return 0
}

dd_dir="$HOME/Library/Developer/Xcode/DerivedData"
mkdir -p "$dd_dir/EligibleBeforeSizing"
touch "$dd_dir/EligibleBeforeSizing/build.o"
clean_xcode_derived_data
EOF

    [ "$status" -eq 0 ] || {
        echo "$output"
        return 1
    }
    [[ "$output" != *"Xcode DerivedData"* ]] || return 1
    [[ "$output" != *"UNEXPECTED_REGISTER"* ]] || return 1
    [[ "$output" != *"UNEXPECTED_ACTIVITY"* ]]
}

@test "clean_xcode_derived_data dry run rechecks Xcode after sizing" {
    run env HOME="$HOME/dry-run-process-race" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc << 'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/app_caches.sh"

DRY_RUN=true
get_path_size_kb() {
    : > "$HOME/xcode-started"
    echo 7
}
_xcode_cleanup_process_state() {
    [[ -e "$HOME/xcode-started" ]] && return 0
    return 1
}
record_dry_run_cleanup_target() { echo "UNEXPECTED_REGISTER:$1"; return 0; }
defer_cleanup_family() { echo "DEFER:$1"; }
note_activity() { :; }

dd_dir="$HOME/Library/Developer/Xcode/DerivedData"
mkdir -p "$dd_dir/EligibleBeforeSizing"
touch "$dd_dir/EligibleBeforeSizing/build.o"
clean_xcode_derived_data
EOF

    [ "$status" -eq 0 ] || {
        echo "$output"
        return 1
    }
    [[ "$output" == *"DEFER:Xcode"* ]] || return 1
    [[ "$output" != *"UNEXPECTED_REGISTER"* ]] || return 1
    [[ "$output" != *"Xcode DerivedData · 1 project"* ]]
}
