#!/usr/bin/env bash
# 05_lint.sh — shellcheck every runbook script when the tool is available.
# Skips (exit 0) with a notice when shellcheck is not installed, so the
# suite stays runnable on a fresh machine.

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
# shellcheck source=lib_test.sh
source tests/lib_test.sh

echo "== 05 lint (shellcheck) =="

if ! command -v shellcheck >/dev/null 2>&1; then
    echo "  skip shellcheck not installed — install it for deeper checks:"
    echo "       sudo dnf install shellcheck     (Fedora)"
    echo "       sudo apt install shellcheck     (Debian/Ubuntu)"
    finish
fi

SCRIPTS=(setup.sh lib.sh
    cli/install.sh cli/setup_shell_functions.sh cli/check.sh
    audio/install.sh audio/uninstall.sh audio/audio_lib.sh audio/check.sh
    fingerprint/install.sh fingerprint/check.sh
    touchscreen/install.sh touchscreen/uninstall.sh touchscreen/check.sh
    color-profiles/install.sh color-profiles/check.sh
    hdr/check.sh)

# SC1091: sourced-file paths can't be resolved statically (we use computed
# paths); SC2317: "unreachable" in sourced stubs. Excluded globally.
for s in "${SCRIPTS[@]}"; do
    if out="$(shellcheck -x -e SC1091,SC2317 "$s" 2>&1)"; then
        _pass "shellcheck: $s"
    else
        _fail "shellcheck: $s"$'\n'"$out"
    fi
done

finish
