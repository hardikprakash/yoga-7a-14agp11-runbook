#!/usr/bin/env bash
# check.sh — read-only status of the cli module (functions + completion).
# Line format consumed by ./setup.sh status: ok:/warn:/fail:/info:

set -euo pipefail
# shellcheck source=../lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

BASHRC="${BASHRC:-$HOME/.bashrc}"
START_MARKER="# === Hardware recovery functions ==="
COMP_MARKER="# === setup.sh tab completion ==="
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
elif [ "$(grep -cF "$START_MARKER" "$BASHRC")" -gt 1 ]; then
    chk_warn "duplicate function blocks in $BASHRC"
    chk_info "re-run ./setup.sh cli to collapse them"
else
    chk_ok "${#REQUIRED_FUNCS[@]} functions in $BASHRC"
fi

# tab completion for setup.sh (installed alongside the functions)
if grep -qF "$COMP_MARKER" "$BASHRC" &&
   grep -q "_setup_runbook()" "$BASHRC"; then
    chk_ok "tab completion for ./setup.sh installed"
elif grep -qF "$COMP_MARKER" "$BASHRC"; then
    chk_warn "completion block present but looks broken (no _setup_runbook)"
    chk_info "re-run ./setup.sh cli to refresh it"
else
    chk_warn "tab completion for ./setup.sh not installed"
    chk_info "run ./setup.sh cli (then: ./setup.sh audio --backend <Tab>)"
fi

chk_info "${REQUIRED_FUNCS[*]}"
chk_info "active in new shells only — source ~/.bashrc after changes"
