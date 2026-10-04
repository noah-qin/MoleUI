#!/bin/bash
# Test helper: load match_apps_by_name directly from bin/uninstall.sh for unit testing.
# Requires apps_data and selected_apps arrays to be defined before sourcing.

# Declared by caller before sourcing this file
: "${apps_data?apps_data array must be set before sourcing this file}"

_test_helper_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_repo_root="$(cd "${_test_helper_dir}/.." && pwd)"
_uninstall_script="${_repo_root}/bin/uninstall.sh"

if [[ ! -f "${_uninstall_script}" ]]; then
    echo "Error: unable to find ${_uninstall_script}" >&2
    return 1
fi

# Suppress color codes in test output
YELLOW=""
NC=""

eval "$(
    sed -n '/^match_apps_by_name()[[:space:]]*{/,/^}$/p' "${_uninstall_script}"
)"

unset _test_helper_dir
unset _repo_root
unset _uninstall_script
