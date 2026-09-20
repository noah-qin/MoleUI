#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT
    export HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$HOME/.config/mole"
}


@test "find with non-existent directory doesn't cause script exit (pipefail bug)" {
    result=$(/bin/bash -c '
        set -euo pipefail
        find /non/existent/dir -name "*.cache" 2>/dev/null || true
        echo "survived"
    ')
    [[ "$result" == "survived" ]]
}

@test "browser directory check pattern is safe when directories don't exist" {
    result=$(/bin/bash -c '
        set -euo pipefail
        search_dirs=()
        [[ -d "/non/existent/chrome" ]] && search_dirs+=("/non/existent/chrome")
        [[ -d "/tmp" ]] && search_dirs+=("/tmp")

        if [[ ${#search_dirs[@]} -gt 0 ]]; then
            find "${search_dirs[@]}" -maxdepth 1 -type f 2>/dev/null || true
        fi
        echo "survived"
    ')
    [[ "$result" == "survived" ]]
}

@test "empty array doesn't cause unbound variable error" {
    result=$(/bin/bash -c '
        set -euo pipefail
        search_dirs=()

        if [[ ${#search_dirs[@]} -gt 0 ]]; then
            echo "should not reach here"
        fi
        echo "survived"
    ')
    [[ "$result" == "survived" ]]
}


@test "version comparison works correctly" {
    result=$(/bin/bash -c '
        v1="1.11.8"
        v2="1.11.9"
        if [[ "$(printf "%s\n" "$v1" "$v2" | sort -V | head -1)" == "$v1" && "$v1" != "$v2" ]]; then
            echo "update_needed"
        fi
    ')
    [[ "$result" == "update_needed" ]]
}

@test "version comparison with same versions" {
    result=$(/bin/bash -c '
        v1="1.11.8"
        v2="1.11.8"
        if [[ "$(printf "%s\n" "$v1" "$v2" | sort -V | head -1)" == "$v1" && "$v1" != "$v2" ]]; then
            echo "update_needed"
        else
            echo "up_to_date"
        fi
    ')
    [[ "$result" == "up_to_date" ]]
}

@test "version prefix v/V is stripped correctly" {
    result=$(/bin/bash -c '
        version="v1.11.9"
        clean=${version#v}
        clean=${clean#V}
        echo "$clean"
    ')
    [[ "$result" == "1.11.9" ]]
}

@test "network timeout prevents hanging (simulated)" {
    if ! command -v gtimeout >/dev/null 2>&1 && ! command -v timeout >/dev/null 2>&1; then
        skip "gtimeout/timeout not available"
    fi

    timeout_cmd="timeout"
    command -v timeout >/dev/null 2>&1 || timeout_cmd="gtimeout"

    # shellcheck disable=SC2016
    result=$($timeout_cmd 5 /bin/bash -c '
        result=$(curl -fsSL --connect-timeout 1 --max-time 2 "http://192.0.2.1:12345/test" 2>/dev/null || echo "failed")
        if [[ "$result" == "failed" ]]; then
            echo "timeout_works"
        fi
    ')
    [[ "$result" == "timeout_works" ]]
}

@test "run_with_timeout perl fallback stops TERM-ignoring commands" {
    local fake_dir="$BATS_TEST_TMPDIR/timeout-bin"
    mkdir -p "$fake_dir"
    local fake_cmd="$fake_dir/hang.sh"

    cat > "$fake_cmd" <<'EOF'
#!/bin/bash
trap "" TERM
sleep 5
EOF
    chmod +x "$fake_cmd"

    run /usr/bin/perl -e 'alarm 5; exec @ARGV' env FAKE_CMD="$fake_cmd" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/timeout.sh"
MO_TIMEOUT_BIN=""
MO_TIMEOUT_PERL_BIN="${MO_TIMEOUT_PERL_BIN:-$(command -v perl)}"
SECONDS=0
set +e
run_with_timeout 1 "$FAKE_CMD"
status=$?
set -e
echo "STATUS=$status ELAPSED=$SECONDS"
EOF
    [ "$status" -eq 0 ]
    [[ "$output" == *"STATUS=124"* ]] || return 1
    elapsed=$(printf '%s\n' "$output" | awk '{for (i = 1; i <= NF; i++) if ($i ~ /^ELAPSED=/) {split($i, kv, "="); print kv[2]}}' | tail -1)
    [[ "$elapsed" =~ ^[0-9]+$ ]] || return 1
    (( elapsed < 6 ))
}

@test "empty version string is handled gracefully" {
    result=$(/bin/bash -c '
        latest=""
        if [[ -z "$latest" ]]; then
            echo "handled"
        fi
    ')
    [[ "$result" == "handled" ]]
}


@test "grep with no match doesn't cause exit in pipefail mode" {
    result=$(/bin/bash -c '
        set -euo pipefail
        echo "test" | grep "nonexistent" || true
        echo "survived"
    ')
    [[ "$result" == "survived" ]]
}

@test "command substitution failure is handled with || true" {
    result=$(/bin/bash -c '
        set -euo pipefail
        output=$(false) || true
        echo "survived"
    ')
    [[ "$result" == "survived" ]]
}

@test "arithmetic on zero doesn't cause exit" {
    result=$(/bin/bash -c '
        set -euo pipefail
        count=0
        ((count++)) || true
        echo "$count"
    ')
    [[ "$result" == "1" ]]
}


@test "safe_remove pattern doesn't fail on non-existent path" {
    result=$(/bin/bash -c "
        set -euo pipefail
        source '$PROJECT_ROOT/lib/core/common.sh'
        safe_remove '$HOME/non/existent/path' true > /dev/null 2>&1 || true
        echo 'survived'
    ")
    [[ "$result" == "survived" ]]
}

@test "module loading doesn't fail" {
    result=$(/bin/bash -c "
        set -euo pipefail
        source '$PROJECT_ROOT/lib/core/common.sh'
        echo 'loaded'
    ")
    [[ "$result" == "loaded" ]]
}

@test "normalize_paths_for_cleanup handles large nested batches without hanging" {
    local limit_ms="${MOLE_PERF_NORMALIZE_PATHS_LIMIT_MS:-10000}"

    run env PROJECT_ROOT="$PROJECT_ROOT" LIMIT_MS="$limit_ms" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail

PYTHON_BIN="${PYTHON_BIN:-}"
if [[ -z "$PYTHON_BIN" ]]; then
    PYTHON_BIN=$(command -v python3 || command -v python || true)
fi
[[ -n "$PYTHON_BIN" ]] || { echo "python unavailable"; exit 127; }

"$PYTHON_BIN" - <<'PY'
from pathlib import Path
import os
project_root = Path(os.environ["PROJECT_ROOT"])
text = (project_root / "bin/clean.sh").read_text()
start = text.index("normalize_paths_for_cleanup() {")
depth = 0
end = None
for i in range(start, len(text)):
    ch = text[i]
    if ch == "{":
        depth += 1
    elif ch == "}":
        depth -= 1
        if depth == 0:
            end = i + 1
            break
Path("/tmp/normalize_paths_for_cleanup.sh").write_text(text[start:end] + "\n")
PY

source /tmp/normalize_paths_for_cleanup.sh

paths=(
    "$HOME/Library/Containers/com.microsoft.Word/Data/Library/Caches"
    "$HOME/Library/Containers/com.microsoft.Excel/Data/Library/Caches/"
)
for i in $(seq 1 6000); do
    paths+=("$HOME/Library/Containers/com.microsoft.Word/Data/Library/Caches/item-$i")
    paths+=("$HOME/Library/Containers/com.microsoft.Excel/Data/Library/Caches/item-$i")
done

start_ns=$("$PYTHON_BIN" - <<'PY'
import time
print(time.time_ns())
PY
)
normalized=()
while IFS= read -r -d '' line; do
    normalized+=("$line")
done < <(normalize_paths_for_cleanup "${paths[@]}")
end_ns=$("$PYTHON_BIN" - <<'PY'
import time
print(time.time_ns())
PY
)
elapsed_ms=$(( (end_ns - start_ns) / 1000000 ))

printf 'COUNT=%s ELAPSED_MS=%s\n' "${#normalized[@]}" "$elapsed_ms"
printf '%s\n' "${normalized[@]}"

[[ ${#normalized[@]} -eq 2 ]] || exit 1
[[ "${normalized[0]}" == "$HOME/Library/Containers/com.microsoft.Excel/Data/Library/Caches" || "${normalized[1]}" == "$HOME/Library/Containers/com.microsoft.Excel/Data/Library/Caches" ]]
[[ "${normalized[0]}" == "$HOME/Library/Containers/com.microsoft.Word/Data/Library/Caches" || "${normalized[1]}" == "$HOME/Library/Containers/com.microsoft.Word/Data/Library/Caches" ]]
(( elapsed_ms < LIMIT_MS ))
EOF

    if [ "$status" -ne 0 ]; then
        printf 'normalize_paths_for_cleanup status=%s\n' "$status" >&3
        printf '%s\n' "$output" >&3
    fi
    [ "$status" -eq 0 ]
    [[ "$output" == *"COUNT=2"* ]]
}

@test "normalize_paths_for_cleanup removes whole Gradle DSL hash dirs" {
    run env PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail

PYTHON_BIN="${PYTHON_BIN:-}"
if [[ -z "$PYTHON_BIN" ]]; then
    PYTHON_BIN=$(command -v python3 || command -v python || true)
fi
[[ -n "$PYTHON_BIN" ]] || { echo "python unavailable"; exit 127; }

"$PYTHON_BIN" - <<'PY'
from pathlib import Path
import os
project_root = Path(os.environ["PROJECT_ROOT"])
text = (project_root / "bin/clean.sh").read_text()
start = text.index("normalize_paths_for_cleanup() {")
depth = 0
end = None
for i in range(start, len(text)):
    ch = text[i]
    if ch == "{":
        depth += 1
    elif ch == "}":
        depth -= 1
        if depth == 0:
            end = i + 1
            break
Path("/tmp/normalize_paths_for_cleanup_gradle.sh").write_text(text[start:end] + "\n")
PY

source /tmp/normalize_paths_for_cleanup_gradle.sh

hash_dir="$HOME/.gradle/caches/8.13/groovy-dsl/abc123"
paths=(
    "$hash_dir/metadata.bin"
    "$hash_dir/classes/cp.bin"
    "$HOME/.gradle/caches/8.13/kotlin-dsl/def456/metadata.bin"
)

normalized=()
while IFS= read -r -d '' line; do
    normalized+=("$line")
done < <(normalize_paths_for_cleanup "${paths[@]}")

printf '%s\n' "${normalized[@]}"

[[ ${#normalized[@]} -eq 2 ]] || exit 1
[[ "${normalized[0]}" == "$HOME/.gradle/caches/8.13/groovy-dsl/abc123" || "${normalized[1]}" == "$HOME/.gradle/caches/8.13/groovy-dsl/abc123" ]]
[[ "${normalized[0]}" == "$HOME/.gradle/caches/8.13/kotlin-dsl/def456" || "${normalized[1]}" == "$HOME/.gradle/caches/8.13/kotlin-dsl/def456" ]]
EOF

    [ "$status" -eq 0 ]
}
