#!/bin/bash
# Canonical optimization task metadata and handler ownership.

set -euo pipefail

if [[ -n "${MOLE_OPTIMIZE_CATALOG_LOADED:-}" ]]; then
    return 0
fi
readonly MOLE_OPTIMIZE_CATALOG_LOADED=1

# The catalog uses aligned arrays instead of serialized records. This keeps
# field boundaries explicit on Bash 3.2 and lets each consumer read only the
# projection it owns. Every registered task is safe for automatic execution.
MOLE_OPTIMIZE_ACTIONS=()
MOLE_OPTIMIZE_HANDLERS=()
MOLE_OPTIMIZE_HEALTH_NAMES=()
MOLE_OPTIMIZE_WHITELIST_NAMES=()
MOLE_OPTIMIZE_DESCRIPTIONS=()
MOLE_OPTIMIZE_SAFE_VALUES=()

_optimize_catalog_register() {
    local index=${#MOLE_OPTIMIZE_ACTIONS[@]}
    MOLE_OPTIMIZE_ACTIONS[index]="$1"
    MOLE_OPTIMIZE_HANDLERS[index]="$2"
    MOLE_OPTIMIZE_HEALTH_NAMES[index]="$3"
    MOLE_OPTIMIZE_WHITELIST_NAMES[index]="$4"
    MOLE_OPTIMIZE_DESCRIPTIONS[index]="$5"
    MOLE_OPTIMIZE_SAFE_VALUES[index]="$6"
}

_optimize_catalog_register system_maintenance opt_system_maintenance \
    "DNS & Spotlight Check" "DNS & Spotlight Check" \
    "Refresh DNS cache & verify Spotlight status" true
_optimize_catalog_register cache_refresh opt_cache_refresh \
    "Finder Cache Refresh" "Finder Cache Refresh" \
    "Refresh QuickLook thumbnails & icon services cache" true
_optimize_catalog_register saved_state_cleanup opt_saved_state_cleanup \
    "App State Cleanup" "App State Cleanup" \
    "Remove old saved application states (30+ days)" true
_optimize_catalog_register fix_broken_configs opt_fix_broken_configs \
    "Broken Config Repair" "Broken Config Repair" \
    "Fix corrupted preferences files" true
_optimize_catalog_register network_optimization opt_network_optimization \
    "Network Cache Refresh" "Network Cache Refresh" \
    "Optimize DNS cache & restart mDNSResponder" true
_optimize_catalog_register sqlite_vacuum opt_sqlite_vacuum \
    "Database Optimization" "Database Optimization" \
    "Compress SQLite databases for Mail, Safari & Messages (skips if apps are running)" true
_optimize_catalog_register launch_services_rebuild opt_launch_services_rebuild \
    "LaunchServices Repair" "LaunchServices Repair" \
    'Repair "Open with" menu & file associations' true
_optimize_catalog_register prevent_network_dsstore opt_prevent_network_dsstore \
    "Prevent Finder .DS_Store" "Prevent Finder .DS_Store" \
    "Set a persistent Finder preference to stop writing .DS_Store on SMB/AFP/NFS and USB volumes" true
_optimize_catalog_register legacy_overrides_audit opt_legacy_overrides_audit \
    "Legacy Overrides" "Legacy Overrides" \
    "Remove hidden App Nap and disk-image verification overrides left by old tweak tools" true
_optimize_catalog_register network_stack_optimize opt_network_stack_optimize \
    "Network Stack Refresh" "Network Stack Refresh" \
    "Flush routing table and ARP cache to resolve network issues" true
_optimize_catalog_register disk_permissions_repair opt_disk_permissions_repair \
    "Permission Repair" "Permission Repair" \
    "Fix user directory permission issues" true
_optimize_catalog_register spotlight_index_optimize opt_spotlight_index_optimize \
    "Spotlight Optimization" "Spotlight Optimization" \
    "Rebuild index if search is slow (smart detection)" true
_optimize_catalog_register spotlight_orphan_rules_cleanup opt_prune_spotlight_orphan_rules \
    "Spotlight Orphan Rules" "Spotlight Orphan Rules" \
    "Remove Spotlight search-rule entries for apps that are no longer installed" true
_optimize_catalog_register periodic_maintenance opt_periodic_maintenance \
    "Periodic Maintenance" "Periodic Maintenance" \
    "Run macOS daily/weekly/monthly maintenance scripts if stale" true
_optimize_catalog_register shared_file_list_repair opt_shared_file_list_repair \
    "Shared File Lists" "Shared File Lists" \
    "Repair corrupted Finder favorites and recent documents" true
_optimize_catalog_register disk_verify opt_disk_verify \
    "Disk Health" "Disk Health" \
    "Verify filesystem integrity" true
_optimize_catalog_register login_items_audit opt_login_items_audit \
    "Login Items" "Login Items Audit" \
    "Audit login items for broken entries" true
_optimize_catalog_register quarantine_cleanup opt_quarantine_cleanup \
    "Quarantine Database Cleanup" "Quarantine Database Cleanup" \
    "Clear Gatekeeper download tracking history" true
_optimize_catalog_register launch_agents_cleanup opt_launch_agents_cleanup \
    "Launch Agents Cleanup" "Launch Agents Cleanup" \
    "Remove broken LaunchAgents whose binaries no longer exist" true
_optimize_catalog_register notification_cleanup opt_notification_cleanup \
    "Notifications" "Notifications" \
    "Clean old delivered notifications to reduce database bloat" true
_optimize_catalog_register coreduet_cleanup opt_coreduet_cleanup \
    "Usage Data" "Usage Data" \
    "Clean old usage tracking data" true

optimize_catalog_index_for() {
    local requested_action="$1"
    local index
    for ((index = 0; index < ${#MOLE_OPTIMIZE_ACTIONS[@]}; index++)); do
        if [[ "${MOLE_OPTIMIZE_ACTIONS[$index]}" == "$requested_action" ]]; then
            printf '%s\n' "$index"
            return 0
        fi
    done
    return 1
}

optimize_catalog_handler_for() {
    local index
    index=$(optimize_catalog_index_for "$1") || return 1
    printf '%s\n' "${MOLE_OPTIMIZE_HANDLERS[$index]}"
}

optimize_catalog_health_name_for() {
    local index
    index=$(optimize_catalog_index_for "$1") || return 1
    printf '%s\n' "${MOLE_OPTIMIZE_HEALTH_NAMES[$index]}"
}

optimize_catalog_validate() {
    local count=${#MOLE_OPTIMIZE_ACTIONS[@]}
    if [[ $count -eq 0 ]]; then
        echo "Optimize task catalog is empty" >&2
        return 1
    fi
    if [[ ${#MOLE_OPTIMIZE_HANDLERS[@]} -ne $count ||
        ${#MOLE_OPTIMIZE_HEALTH_NAMES[@]} -ne $count ||
        ${#MOLE_OPTIMIZE_WHITELIST_NAMES[@]} -ne $count ||
        ${#MOLE_OPTIMIZE_DESCRIPTIONS[@]} -ne $count ||
        ${#MOLE_OPTIMIZE_SAFE_VALUES[@]} -ne $count ]]; then
        echo "Optimize task catalog fields are misaligned" >&2
        return 1
    fi

    local seen_actions="|"
    local seen_handlers="|"
    local index action handler
    for ((index = 0; index < count; index++)); do
        action=${MOLE_OPTIMIZE_ACTIONS[$index]}
        handler=${MOLE_OPTIMIZE_HANDLERS[$index]}
        if [[ ! "$action" =~ ^[a-z0-9_]+$ || ! "$handler" =~ ^opt_[a-z0-9_]+$ ]]; then
            echo "Invalid optimize task identity: $action|$handler" >&2
            return 1
        fi
        if [[ -z "${MOLE_OPTIMIZE_HEALTH_NAMES[$index]}" ||
            -z "${MOLE_OPTIMIZE_WHITELIST_NAMES[$index]}" ||
            -z "${MOLE_OPTIMIZE_DESCRIPTIONS[$index]}" ]]; then
            echo "Optimize task metadata is incomplete: $action" >&2
            return 1
        fi
        if [[ "${MOLE_OPTIMIZE_SAFE_VALUES[$index]}" != "true" ]]; then
            echo "Optimize task is not safe for automatic execution: $action" >&2
            return 1
        fi
        if [[ "$seen_actions" == *"|$action|"* ]]; then
            echo "Duplicate optimize task action: $action" >&2
            return 1
        fi
        if [[ "$seen_handlers" == *"|$handler|"* ]]; then
            echo "Duplicate optimize task handler: $handler" >&2
            return 1
        fi
        seen_actions+="$action|"
        seen_handlers+="$handler|"
    done
}

optimize_catalog_validate
readonly -a MOLE_OPTIMIZE_ACTIONS
readonly -a MOLE_OPTIMIZE_HANDLERS
readonly -a MOLE_OPTIMIZE_HEALTH_NAMES
readonly -a MOLE_OPTIMIZE_WHITELIST_NAMES
readonly -a MOLE_OPTIMIZE_DESCRIPTIONS
readonly -a MOLE_OPTIMIZE_SAFE_VALUES
unset -f _optimize_catalog_register
