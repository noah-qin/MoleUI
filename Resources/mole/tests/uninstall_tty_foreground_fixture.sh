#!/bin/bash

set -euo pipefail

PROJECT_ROOT="$1"

# shellcheck source=lib/core/timeout.sh
source "$PROJECT_ROOT/lib/core/timeout.sh"

if mole_tty_is_foreground; then
    printf 'TTY-STATE:foreground\n'
else
    printf 'TTY-STATE:background\n'
fi
