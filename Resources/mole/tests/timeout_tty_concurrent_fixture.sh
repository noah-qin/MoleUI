#!/bin/bash

set -uo pipefail

PROJECT_ROOT="$1"

# shellcheck source=lib/core/timeout.sh
source "$PROJECT_ROOT/lib/core/timeout.sh"

MO_TIMEOUT_BIN=""
MO_TIMEOUT_PERL_BIN="/usr/bin/perl"

# Mole runs timeout helpers concurrently inside a single process group (the
# uninstall scan workers). Only the helper whose process group actually owns
# the terminal may hand it to its child: a helper that hands off while a
# sibling's child owns the terminal also restores the terminal to that
# sibling's child, which is a dead or reaped process group by then, and the
# script is left without the terminal. The next prompt read then stops on
# SIGTTIN and the uninstall hangs before removing anything (#1222, #1218).
#
# Here the background worker takes the terminal first and keeps it for 2s. The
# foreground helper below starts inside that window, so its child must report
# that it does NOT own the terminal.
(run_with_timeout 5 /bin/sleep 2) < /dev/tty &
worker=$!

/bin/sleep 0.3

# shellcheck disable=SC2016  # Embedded Perl uses Perl variables inside single quotes.
run_with_timeout 3 /usr/bin/perl -e '
    use POSIX qw(tcgetpgrp);
    my $owner = -t STDIN ? tcgetpgrp(0) : -1;
    printf "CHILD:%s\n", ($owner == getpgrp() ? "OWNS" : "NOT-OWNS");
'

wait "$worker" 2> /dev/null || true

printf 'READY\n'
read -r value
printf 'READ:%s\n' "$value"
