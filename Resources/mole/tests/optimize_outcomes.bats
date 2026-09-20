#!/usr/bin/env bats

setup_file() {
	PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
	export PROJECT_ROOT
}

@test "optimize outcomes record one result per task" {
	run env PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/optimize/outcomes.sh"

optimize_outcomes_reset
optimize_task_start
optimize_task_result "$MOLE_OPTIMIZE_OUTCOME_APPLIED"
optimize_task_finish system_maintenance

[[ "$(optimize_outcome_count applied)" == "1" ]] || exit 1
[[ "$(optimize_outcome_count unchanged)" == "0" ]] || exit 1
[[ "$(optimize_outcome_total)" == "1" ]] || exit 1
EOF

	[[ "$status" -eq 0 ]] || { echo "$output"; return 1; }
}

@test "optimize outcomes distinguish unresolved attention from failure" {
	run env PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/optimize/outcomes.sh"

optimize_outcomes_reset
optimize_task_start
optimize_task_result "$MOLE_OPTIMIZE_OUTCOME_ATTENTION"
optimize_task_finish login_items_audit

[[ "$(optimize_outcome_count attention)" == "1" ]] || exit 1
[[ "$(optimize_outcome_count failed)" == "0" ]] || exit 1
EOF

	[[ "$status" -eq 0 ]] || { echo "$output"; return 1; }
}

@test "optimize outcome counts give failures precedence over partial changes" {
	run env PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/optimize/outcomes.sh"

optimize_outcomes_reset
optimize_task_start
optimize_task_result_from_counts 2 1 0
optimize_task_finish sqlite_vacuum

[[ "$(optimize_outcome_count failed)" == "1" ]] || exit 1
[[ "$(optimize_outcome_count applied)" == "0" ]] || exit 1
EOF

	[[ "$status" -eq 0 ]] || { echo "$output"; return 1; }
}

@test "optimize run success rejects failed tasks but allows attention" {
	run env PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/optimize/outcomes.sh"

optimize_task_start
optimize_task_result "$MOLE_OPTIMIZE_OUTCOME_ATTENTION"
optimize_task_finish login_items_audit
optimize_outcomes_succeeded || exit 1

optimize_task_start
optimize_task_result "$MOLE_OPTIMIZE_OUTCOME_FAILED"
optimize_task_finish periodic_maintenance
if optimize_outcomes_succeeded; then
    exit 1
fi
EOF

	[[ "$status" -eq 0 ]] || { echo "$output"; return 1; }
}

@test "optimize outcomes reject invalid and duplicate task results" {
	run env PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/optimize/outcomes.sh"

if optimize_task_result invented; then
    echo "invalid outcome accepted"
    exit 1
fi

optimize_task_start
optimize_task_result "$MOLE_OPTIMIZE_OUTCOME_UNCHANGED"
if optimize_task_result "$MOLE_OPTIMIZE_OUTCOME_APPLIED"; then
    echo "second task outcome accepted"
    exit 1
fi
EOF

	[[ "$status" -eq 0 ]] || { echo "$output"; return 1; }
	[[ "$output" == *"Invalid optimize task outcome: invented"* ]] || return 1
	[[ "$output" == *"Optimize task outcome is already set: unchanged"* ]] || return 1
}

@test "optimize outcomes reject results outside an active task" {
	run env PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/optimize/outcomes.sh"

if optimize_task_result "$MOLE_OPTIMIZE_OUTCOME_APPLIED"; then
    echo "inactive task outcome accepted"
    exit 1
fi
EOF

	[[ "$status" -eq 0 ]] || { echo "$output"; return 1; }
	[[ "$output" == *"Optimize task was not started"* ]] || return 1
}

@test "optimize outcomes reject missing and duplicate task records" {
	run env PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/optimize/outcomes.sh"

optimize_task_start
if optimize_task_finish periodic_maintenance; then
    echo "missing task outcome accepted"
    exit 1
fi

optimize_task_result "$MOLE_OPTIMIZE_OUTCOME_UNAVAILABLE"
optimize_task_finish periodic_maintenance
optimize_task_start
optimize_task_result "$MOLE_OPTIMIZE_OUTCOME_UNCHANGED"
if optimize_task_finish periodic_maintenance; then
    echo "duplicate task record accepted"
    exit 1
fi
EOF

	[[ "$status" -eq 0 ]] || { echo "$output"; return 1; }
	[[ "$output" == *"Optimize task did not report an outcome: periodic_maintenance"* ]] || return 1
	[[ "$output" == *"Optimize task outcome is already recorded: periodic_maintenance"* ]] || return 1
}

@test "optimize outcomes expose failed actions without leaking ledger storage" {
	run env PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/optimize/outcomes.sh"

for record in "cache_refresh:applied" "disk_verify:failed" "login_items_audit:attention" "periodic_maintenance:failed"; do
    action=${record%%:*}
    outcome=${record#*:}
    optimize_task_start
    optimize_task_result "$outcome"
    optimize_task_finish "$action"
done

expected=$(printf 'disk_verify\nperiodic_maintenance\n')
[[ "$(optimize_failed_actions)" == "$expected" ]] || exit 1
if grep -q 'MOLE_OPTIMIZE_RESULT_' "$PROJECT_ROOT/bin/optimize.sh"; then
    echo "optimize command reads private outcome storage"
    exit 1
fi
EOF

	[[ "$status" -eq 0 ]] || { echo "$output"; return 1; }
}
