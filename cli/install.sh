#!/usr/bin/env bash
# install.sh — module entry point; delegates to setup_shell_functions.sh.

set -euo pipefail
# shellcheck source=../lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

usage() {
    cat <<EOF
cli module — hardware recovery shell functions in ~/.bashrc.

  ./install.sh [--dry-run]

Installs: bt_reset, bt_audio_reset, audio_reset, wifi_reset.
Each escalates to a kernel-module reload only if its light-path check
fails. Re-running refreshes the block in place (idempotent).
EOF
}

parse_common_flags "$@"
refuse_root

args=()
[ "$DRY_RUN" = 1 ] && args+=(--dry-run)
bash "$RUNBOOK_ROOT/cli/setup_shell_functions.sh" ${args[@]+"${args[@]}"}
