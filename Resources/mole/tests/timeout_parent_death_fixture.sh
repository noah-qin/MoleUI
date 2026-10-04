#!/bin/bash

set -uo pipefail

PROJECT_ROOT="$1"
CHILD_PID_FILE="$2"

# shellcheck source=lib/core/timeout.sh
source "$PROJECT_ROOT/lib/core/timeout.sh"

MO_TIMEOUT_BIN=""
MO_TIMEOUT_PERL_BIN="/usr/bin/perl"

# shellcheck disable=SC2016  # The inner bash expands $$ and $1.
run_with_timeout 30 /bin/bash --noprofile --norc -c '
    printf "%s\n" "$$" > "$1"
    while :; do
        /bin/sleep 1
    done
' timeout-child "$CHILD_PID_FILE"
