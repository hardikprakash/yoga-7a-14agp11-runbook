#!/usr/bin/env bash
# uninstall.sh — remove the WACF2200 touchscreen workaround (needs sudo).

set -euo pipefail
# shellcheck source=../lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

usage() {
    cat <<EOF
touchscreen module — remove the rebind workaround.

  ./uninstall.sh [--dry-run] [--yes]
EOF
}

parse_common_flags "$@"
refuse_root

log_step "touchscreen: removing wacf2200-rebind (sudo, after confirmation)"

if ! confirm "Disable and delete wacf2200-rebind.service and its script?"; then
    die "declined"
fi

run sudo systemctl disable --now wacf2200-rebind.service 2>/dev/null || true
run sudo rm -f /etc/systemd/system/wacf2200-rebind.service /usr/local/bin/wacf2200-rebind.sh
run sudo systemctl daemon-reload

echo
log_ok "removed. Reboot to drop the running instance."
