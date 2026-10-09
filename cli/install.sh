#!/usr/bin/env bash
# install.sh — module entry point; delegates to setup_shell_functions.sh
# (recovery functions) and setup_bash_completion.sh (tab completion).

set -euo pipefail
# shellcheck source=../lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

usage() {
    cat <<EOF
cli module — shell functions + tab completion for ~/.bashrc.

  ./install.sh [--dry-run]

Installs: bt_reset, bt_audio_reset, audio_reset, wifi_reset (each
escalates to a kernel-module reload only if its light-path check fails)
plus bash tab completion for ./setup.sh flags (context-aware: --backend,
--variant, --force appear only after audio/all). Re-running refreshes
both blocks in place (idempotent).
EOF
}

parse_common_flags "$@"
refuse_root

args=()
[ "$DRY_RUN" = 1 ] && args+=(--dry-run)
bash "$RUNBOOK_ROOT/cli/setup_shell_functions.sh" ${args[@]+"${args[@]}"}
bash "$RUNBOOK_ROOT/cli/setup_bash_completion.sh" ${args[@]+"${args[@]}"}
