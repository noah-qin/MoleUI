#!/usr/bin/env python3
"""Check that menu search keeps a pasted term under the system Bash."""
import fcntl
import os
import pty
import select
import signal
import subprocess
import tempfile
import termios
import time
from pathlib import Path

root = Path(__file__).resolve().parents[1]

child_script = r'''
source "$TEST_ROOT/lib/core/common.sh"
source "$TEST_ROOT/lib/ui/menu_paginated.sh"
set +e
items=()
for ((i = 1; i <= 40; i++)); do items+=("App $i"); done
items+=("zebra target")
paginated_multi_select "Pick" "${items[@]}"
'''


def read_until(master, output, marker, timeout):
    deadline = time.monotonic() + timeout
    while marker not in output:
        assert time.monotonic() < deadline, ('missing ' + repr(marker), output[-2000:])
        if select.select([master], [], [], .02)[0]:
            output += os.read(master, 65536)
    return output


def check_search(keys):
    with tempfile.TemporaryDirectory(prefix="mole-menu-search-") as home:
        master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, b'\x28\x00\x78\x00\x00\x00\x00\x00')
        env = dict(os.environ, HOME=home, TERM="xterm-256color",
                   MOLE_TEST_MODE="1", MOLE_TEST_NO_AUTH="1", TEST_ROOT=str(root))

        def own_terminal():
            os.setsid()
            fcntl.ioctl(0, termios.TIOCSCTTY, 0)

        process = subprocess.Popen(
            ["/bin/bash", "--noprofile", "--norc", "-c", child_script],
            stdin=slave, stdout=slave, stderr=slave, env=env,
            preexec_fn=own_terminal)
        output = b''
        try:
            output = read_until(master, output, b'selected', 10)
            os.write(master, b'/')
            output = read_until(master, output, b'type to search', 5)
            keys(master)
            output = read_until(master, output, b'Search: zebra_', 5)
            print('PASS: search kept the full term')
        finally:
            if process.poll() is None:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except PermissionError:
                    process.kill()
                # Darwin holds an exiting session leader until its terminal
                # output drains, so keep reading while waiting for the exit.
                deadline = time.monotonic() + 5
                while process.poll() is None and time.monotonic() < deadline:
                    if select.select([master], [], [], .02)[0]:
                        try:
                            os.read(master, 65536)
                        except OSError:
                            break
                process.wait(timeout=5)
            os.close(slave)
            os.close(master)


def paste(master):
    os.write(master, b'zebra')


def fast_typing(master):
    for char in b'zebra':
        os.write(master, bytes([char]))
        time.sleep(.02)


def after_partial_escape(master):
    # Shift+Up is only partly decoded; its tail must not become search text.
    # Keep reading while waiting: a blocked redraw would delay the drain past
    # the next write and flush it too.
    os.write(master, b'\x1b[1;2A')
    deadline = time.monotonic() + .5
    while time.monotonic() < deadline:
        if select.select([master], [], [], .02)[0]:
            os.read(master, 65536)
    os.write(master, b'zebra')


check_search(paste)
check_search(fast_typing)
check_search(after_partial_escape)
