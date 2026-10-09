#!/usr/bin/env bash
# check.sh — read-only status of the cli module.
# Line format consumed by ./setup.sh status: ok:/warn:/fail:/info:

set -euo pipefail
# shellcheck source=../lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

BASHRC="${BASHRC:-$HOME/.bashrc}"
START_MARKER="# === Hardware recovery functions ==="
REQUIRED_FUNCS=(bt_reset bt_audio_reset audio_reset wifi_reset)

if [ ! -f "$BASHRC" ]; then
    chk_fail "no $BASHRC"
    chk_info "run ./setup.sh cli"
    exit 1
fi

if ! grep -qF "$START_MARKER" "$BASHRC"; then
    chk_fail "functions not installed in $BASHRC"
    chk_info "run ./setup.sh cli"
    exit 1
fi

missing=()
for f in "${REQUIRED_FUNCS[@]}"; do
    grep -q "^${f}()" "$BASHRC" || missing+=("$f")
done

if [ "${#missing[@]}" -gt 0 ]; then
    chk_warn "outdated block, missing: ${missing[*]}"
    chk_info "re-run ./setup.sh cli to refresh (idempotent, replaces the old block)"
    exit 0
fi

n_blocks=$(grep -cF "$START_MARKER" "$BASHRC")
if [ "$n_blocks" -gt 1 ]; then
    chk_warn "$n_blocks duplicate blocks in $BASHRC"
    chk_info "re-run ./setup.sh cli to collapse them"
    exit 0
fi

chk_ok "${#REQUIRED_FUNCS[@]} functions in $BASHRC"
chk_info "${REQUIRED_FUNCS[*]}"
chk_info "active in new shells only — source ~/.bashrc after changes"
