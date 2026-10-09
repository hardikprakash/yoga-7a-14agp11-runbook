#!/usr/bin/env bash
# run_tests.sh — run the whole runbook test suite.
#
#   tests/run_tests.sh              run everything
#   tests/run_tests.sh 02           run only tests matching "02"
#
# The suite is safe by construction: it refuses to run as root, sandboxes
# HOME, and puts PATH stubs in front of every mutating command (see
# tests/lib_test.sh). No sudo, no network, no changes to the real system.

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    echo "FATAL: do not run the test suite as root" >&2
    exit 1
fi

filter="${1:-}"
tests=(tests/0[0-9]_*.sh)
ran=0
failed=0

echo "runbook test suite"
echo "=================="

for t in "${tests[@]}"; do
    [ -f "$t" ] || continue
    if [ -n "$filter" ] && [[ "$(basename "$t")" != *"$filter"* ]]; then
        continue
    fi
    ran=$((ran + 1))
    echo
    if bash "$t"; then
        :
    else
        failed=$((failed + 1))
    fi
done

echo
echo "=================="
if [ "$ran" -eq 0 ]; then
    echo "no tests matched filter: $filter" >&2
    exit 2
elif [ "$failed" -eq 0 ]; then
    echo "ALL $ran test file(s) PASSED"
    exit 0
else
    echo "$failed of $ran test file(s) FAILED" >&2
    exit 1
fi
