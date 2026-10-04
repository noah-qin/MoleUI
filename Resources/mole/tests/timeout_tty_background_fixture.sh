#!/bin/bash
# Regression fixture for issue #1222.
#
# The perl timeout fallback hands the controlling terminal to its timed child
# whenever stdin is a tty, so nested sudo inside the child can prompt (#1201).
# bin/uninstall.sh, however, calls run_with_timeout from background metadata and
# scan workers that have no use for the terminal. When such a worker inherits
# the tty on stdin, this handoff steals the terminal's foreground process group
# from the foreground script, which then stops with SIGTTIN at its confirmation
# prompt before anything is uninstalled.
#
# This fixture reports whether the timed child captured the controlling
# terminal's foreground process group:
#   MODE=tty      - stdin is the tty; the handoff must happen (#1201 preserved)
#   MODE=devnull  - stdin is /dev/null; the handoff must be skipped (#1222 fix)
#
# The child reads the foreground pgrp via /dev/tty (the controlling terminal),
# so the probe works even when its own stdin is /dev/null.

set -uo pipefail

PROJECT_ROOT="$1"
MODE="${2:-devnull}"

# shellcheck source=lib/core/timeout.sh
source "$PROJECT_ROOT/lib/core/timeout.sh"

# Force the perl fallback: this is the path that performs the tty handoff.
MO_TIMEOUT_BIN=""
MO_TIMEOUT_PERL_BIN="/usr/bin/perl"

caller_pgrp=$(ps -o pgid= -p $$ | tr -d ' ')

export MOLE_TTY_PROBE_MODE="$MODE"

# The handoff is not synchronous with this child starting: run_with_timeout's
# perl parent calls tcsetpgrp *after* forking, so sampling the foreground group
# the instant the child runs can legitimately still show the caller's group.
# That raced on CI while passing 30 consecutive local runs. Wait for the handoff
# in tty mode instead of racing it, and in devnull mode let the terminal settle
# first, so a delayed handoff would still be caught rather than sampled past.
# shellcheck disable=SC2016  # Perl source; $pgrp/$tty/$fg are Perl variables.
child_probe='
    use POSIX qw(tcgetpgrp);
    my $pgrp = getpgrp();
    open(my $tty, "<", "/dev/tty") or exit 3;
    my $fg = tcgetpgrp(fileno($tty));
    if (($ENV{MOLE_TTY_PROBE_MODE} || "") eq "tty") {
        for (1 .. 200) {
            last if $fg == $pgrp;
            select(undef, undef, undef, 0.01);
            $fg = tcgetpgrp(fileno($tty));
        }
    } else {
        select(undef, undef, undef, 0.2);
        $fg = tcgetpgrp(fileno($tty));
    }
    print "CHILD_PGRP=$pgrp FG=$fg\n";
'

if [[ "$MODE" == "tty" ]]; then
    run_with_timeout 3 /usr/bin/perl -e "$child_probe"
else
    run_with_timeout 3 /usr/bin/perl -e "$child_probe" < /dev/null
fi

echo "CALLER_PGRP=$caller_pgrp"
