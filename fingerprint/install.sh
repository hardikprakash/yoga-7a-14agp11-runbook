#!/usr/bin/env bash
# install.sh — install fprintd/libfprint (the sensor driver stack).
# Finger enrollment is interactive and cannot be scripted:
# it prints the enroll command instead.

set -euo pipefail
# shellcheck source=../lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

usage() {
    cat <<EOF
fingerprint module — install the fingerprint sensor stack.

  ./install.sh [--dry-run] [--yes]

Installs fprintd + libfprint (Fedora Workstation does not ship libfprint
by default on a minimal install). Enrollment itself is interactive:

    fprintd-enroll $USER

then verify with:  ./check.sh
EOF
}

parse_common_flags "$@"
refuse_root

log_step "fingerprint: installing sensor stack"

# Distro package name mapping — libfprint is the driver library, fprintd
# is the daemon + PAM integration that actually exposes the sensor.
declare -A PKGS=(
    [dnf]="fprintd libfprint"
    [apt]="fprintd libfprint2"
    [pacman]="fprintd libfprint"
    [zypper]="fprintd libfprint"
)
mgr="$(pkg_manager)"
[ "$mgr" = none ] && die "no supported package manager found"

mapfile -t wanted < <(tr ' ' '\n' <<<"${PKGS[$mgr]}")
missing=()
for p in "${wanted[@]}"; do
    [ -n "$p" ] || continue
    pkg_installed "$p" || missing+=("$p")
done

if [ "${#missing[@]}" -eq 0 ]; then
    log_ok "already installed: ${wanted[*]}"
else
    log_info "missing: ${missing[*]}"
    pkg_install "${missing[@]}" || die "declined — cannot continue without the sensor stack"
fi

echo
log_ok "sensor stack ready. Enrollment is interactive — run:"
printf '    fprintd-enroll %s\n\n' "$USER"
log_info "then verify with ./setup.sh status (or ./fingerprint/check.sh)"
