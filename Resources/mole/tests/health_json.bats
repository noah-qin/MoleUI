#!/usr/bin/env bats
# get_memory_info must scale vm_stat page counts by vm_stat's own page size
# (16384 on Apple Silicon), not a hardcoded 4096, or memory_used_gb in the
# status JSON reads 4x low on Apple Silicon.

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT
}

@test "get_memory_info uses vm_stat's declared page size" {
    run env PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh" 2> /dev/null || true
source "$PROJECT_ROOT/lib/check/health_json.sh"

# 1,000,000 pages active+wired+compressed at 16384 bytes each = ~15.26 GiB.
sysctl() {
    case "$*" in
        *hw.memsize*) echo $((64 * 1024 * 1024 * 1024)) ;;
        *hw.pagesize*) echo 16384 ;;
        *) command sysctl "$@" ;;
    esac
}
vm_stat() {
    cat <<'VMSTAT'
Mach Virtual Memory Statistics: (page size of 16384 bytes)
Pages active:                            500000.
Pages wired down:                        300000.
Pages occupied by compressor:            200000.
VMSTAT
}

get_memory_info
EOF

    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    # used = (500000+300000+200000)*16384 bytes = 15.26 GiB, not 3.8 (4096).
    used="${output%% *}"
    awk -v u="$used" 'BEGIN { exit !(u > 14 && u < 17) }' || { echo "used_gb=$used (expected ~15.3, 4096 would give ~3.8)"; return 1; }
}
