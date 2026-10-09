#!/usr/bin/env bash
# check.sh — read-only status of the fingerprint module.
# Probes fprintd-list: sensor present? fingers enrolled?

set -euo pipefail
# shellcheck source=../lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

if ! command -v fprintd-list >/dev/null 2>&1; then
    chk_fail "fprintd not installed"
    chk_info "run ./setup.sh fingerprint"
    exit 1
fi

out="$(fprintd-list "$USER" 2>&1 || true)"

# fprintd-list prints: "found N devices" / "found 0 devices"
n_devices=$(sed -n 's/^found \([0-9]*\) devices\?.*/\1/p' <<<"$out" | head -n1)
if [ "${n_devices:-0}" -eq 0 ] 2>/dev/null; then
    chk_fail "no fingerprint sensor detected"
    chk_info "dmesg | grep -i -E 'goodix|fingerprint|spi' to investigate"
    exit 1
fi

if grep -qi "PermissionDenied\|Not Authorized" <<<"$out"; then
    chk_warn "sensor present, but cannot query enrollment for $USER"
    chk_info "try: fprintd-list $USER (or check fprintd service: systemctl status fprintd)"
    exit 0
fi

if grep -qi "has no fingers enrolled" <<<"$out"; then
    sensor=$(sed -n 's/.*enrolled for \(.*\)\.$/\1/p' <<<"$out" | head -n1)
    chk_warn "sensor detected (${sensor:-unknown}), no fingers enrolled"
    chk_info "enroll interactively: fprintd-enroll $USER"
    exit 0
fi

if grep -qiE "has [0-9]+ finger" <<<"$out"; then
    summary=$(grep -oiE "[0-9]+ fingers? enrolled" <<<"$out" | head -n1)
    chk_ok "sensor enrolled (${summary:-fingers on file})"
    chk_info "verify by locking the session and unlocking with a finger"
    exit 0
fi

# Device found, but the output matched none of the known shapes.
chk_warn "sensor present, enrollment state unclear"
chk_info "inspect manually: fprintd-list $USER"
