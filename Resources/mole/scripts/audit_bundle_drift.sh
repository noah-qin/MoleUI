#!/bin/bash
# Bundle drift audit.
#
# Enumerates bundle IDs of all apps in /System/Applications and /Applications
# on the current macOS host, then reports any that are NOT covered by
# SYSTEM_CRITICAL_BUNDLES / DATA_PROTECTED_BUNDLES.
#
# Intent: when a new macOS major release adds a system component (e.g. Apple
# Intelligence introduced new daemons), this script surfaces it so we can
# decide whether to add it to the protection list.
#
# This is a HINT, not an enforcement. New bundle IDs in /Applications may be
# legitimately user-installed (Slack, Discord, etc.) and should NOT be in the
# critical list. Review each match by hand.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

# shellcheck source=lib/core/common.sh
source "$PROJECT_ROOT/lib/core/common.sh"

list_bundle_ids() {
    local dir="$1"
    [[ -d "$dir" ]] || return 0
    find "$dir" -maxdepth 2 -name '*.app' -print 2> /dev/null | while IFS= read -r app; do
        local info="$app/Contents/Info.plist"
        [[ -f "$info" ]] || continue
        plutil -extract CFBundleIdentifier raw "$info" 2> /dev/null || true
    done
}

is_covered() {
    local bundle="$1"
    local pattern
    for pattern in "${SYSTEM_CRITICAL_BUNDLES[@]}" "${DATA_PROTECTED_BUNDLES[@]}"; do
        if bundle_matches_pattern "$bundle" "$pattern"; then
            return 0
        fi
    done
    return 1
}

echo "Mole bundle drift audit"
echo "macOS: $(sw_vers -productVersion 2> /dev/null || echo unknown)"
echo

declare -a system_uncovered=()
declare -a apps_uncovered=()

while IFS= read -r bundle; do
    [[ -n "$bundle" ]] || continue
    if ! is_covered "$bundle"; then
        system_uncovered+=("$bundle")
    fi
done < <(list_bundle_ids /System/Applications | sort -u)

while IFS= read -r bundle; do
    [[ -n "$bundle" ]] || continue
    if ! is_covered "$bundle"; then
        apps_uncovered+=("$bundle")
    fi
done < <(list_bundle_ids /Applications | sort -u)

echo "=== /System/Applications NOT in protection lists ==="
if [[ ${#system_uncovered[@]} -gt 0 ]]; then
    printf '  %s\n' "${system_uncovered[@]}"
    echo
    echo "ACTION: Add legitimately-system bundle IDs above to SYSTEM_CRITICAL_BUNDLES"
    echo "        in lib/core/app_protection_data.sh after review."
else
    echo "  (none -- all system apps covered)"
fi
echo

echo "=== /Applications NOT in protection lists (informational) ==="
if [[ ${#apps_uncovered[@]} -gt 0 ]]; then
    printf '  %s\n' "${apps_uncovered[@]}"
    echo
    echo "NOTE: These are user-installed apps. Most should NOT be protected."
    echo "      Only add if they hold sensitive data that must survive cleanup."
else
    echo "  (none)"
fi

if [[ ${#system_uncovered[@]} -gt 0 ]]; then
    exit 2
fi
