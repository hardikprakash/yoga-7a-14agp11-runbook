#!/usr/bin/env bash
# check.sh — read-only status of the touchscreen module.
# Probes: script installed? service enabled/active? touch input registered?

set -euo pipefail
# shellcheck source=../lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

SCRIPT=/usr/local/bin/wacf2200-rebind.sh
UNIT=wacf2200-rebind.service

if [ ! -f "$SCRIPT" ]; then
    chk_fail "rebind script not installed ($SCRIPT)"
    chk_info "run ./setup.sh touchscreen (needs sudo + reboot)"
    exit 1
fi

# Capture-then-grep throughout: `... | grep -q` under `set -o pipefail`
# reads as failure whenever grep exits early (SIGPIPE on the producer), even
# on a match.
unit_files="$(systemctl list-unit-files "$UNIT" 2>/dev/null)" || true
if ! grep -q "$UNIT" <<<"$unit_files"; then
    chk_fail "script present but $UNIT missing"
    chk_info "run ./setup.sh touchscreen"
    exit 1
fi

enabled="$(systemctl is-enabled "$UNIT" 2>/dev/null || echo unknown)"
if [ "$enabled" != enabled ]; then
    chk_warn "service installed but not enabled ($enabled)"
    chk_info "run ./setup.sh touchscreen"
else
    chk_ok "service installed + enabled"
fi

# Did it actually run this boot, and did the touch device register?
# Capture-then-grep: `journalctl | grep -q` can SIGPIPE under pipefail.
rebind_log="$(journalctl -b -t wacf2200-rebind --no-pager 2>/dev/null)" || true
if grep -q "Rebind complete" <<<"$rebind_log"; then
    chk_ok "rebind ran this boot (journalctl -b -t wacf2200-rebind)"
else
    chk_warn "rebind has not run this boot yet (needs a reboot after install)"
    chk_info "verify after reboot: journalctl -b -t wacf2200-rebind"
fi

if grep -qi "WACF\|wacom" /proc/bus/input/devices 2>/dev/null; then
    chk_ok "Wacom touch/stylus input devices registered"
else
    chk_warn "no Wacom input device yet — touch may not work until the rebind runs"
    chk_info "see touchscreen/README.md if it persists after reboot"
fi
