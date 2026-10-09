#!/usr/bin/env bash
# uninstall.sh — symmetric removal of the HDR EDID workaround.
#
#   ./uninstall.sh [--dry-run] [--yes]
#
# Why this wrapper exists: the upstream hdr-edid-fix/uninstall.sh seds
# /etc/default/grub and /etc/kernel/cmdline, but on BLS systems
# (GRUB_ENABLE_BLSCFG=true, Fedora) the live cmdline also lives in
# /boot/loader/entries/*.conf — which grubby owns and the seds miss.
# Leftover param + deleted firmware file = the kernel asks for a file
# that no longer exists at every boot.
#
# Order matters and is the safety property here:
#   1. grubby --remove-args FIRST — if this fails, we stop before the
#      firmware file is deleted, so the state stays consistent
#   2. upstream uninstall.sh (config seds + firmware + dracut hook)
#   3. dracut -f — the upstream regen step misses Fedora's tooling
#      (no dracut-rebuild, grub2-mkconfig not called), same gap as install
#
# User-level invocation, sudo per step after one confirmation. Reinstall
# afterwards: cd hdr/hdr-edid-fix && sudo ./install.sh (+ grubby on BLS,
# see hdr/README.md).

set -euo pipefail
# shellcheck source=../lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

usage() {
    cat <<EOF
hdr module — remove the HDR EDID workaround.

  ./uninstall.sh [--dry-run] [--yes]

Removes, in this order (the order is the safety):
  1. the kernel cmdline param everywhere grubby put it — BLS entries,
     /etc/default/grub, /etc/kernel/cmdline (grubby --remove-args)
  2. the upstream uninstall: config seds + /usr/lib/firmware/edid/
     hdr-patched-edid.bin + the dracut hook
  3. dracut -f — rebuilds the initramfs without the file (Fedora's
     tooling is missed by the upstream regen step)

If step 1 fails, nothing else runs — never 'param set, file deleted'.
EOF
}

parse_common_flags "$@"
refuse_root

FIX="$RUNBOOK_ROOT/hdr/hdr-edid-fix"
UPSTREAM_UNINSTALL="$FIX/uninstall.sh"
[ -d "$FIX/.git" ] || die "hdr-edid-fix not cloned — nothing to uninstall (run ./setup.sh hdr first)"

# Work out exactly which param is set (don't guess the connector).
# Exclude quotes: /etc/default/grub wraps the value in "...", and a
# captured trailing quote would poison grubby --remove-args.
staged_param="$(grep -ohE 'drm\.edid_firmware=[^[:space:]\"'\'']+' \
    /etc/default/grub /etc/kernel/cmdline /proc/cmdline 2>/dev/null | head -n1 || true)"
if [ -z "$staged_param" ]; then
    # Nothing readable mentions it; fall back to the standard connector so
    # grubby still sweeps BLS entries (unreadable without root).
    CONNECTOR="${CONNECTOR:-}"
    if [ -z "$CONNECTOR" ]; then
        for c in /sys/class/drm/card*-eDP-*; do
            [ -e "$c/status" ] || continue
            [ "$(cat "$c/status")" = "connected" ] || continue
            CONNECTOR="${c##*/}"; CONNECTOR="${CONNECTOR#card*-}"
            break
        done
    fi
    [ -n "$CONNECTOR" ] || die "no staged param found and no connected eDP panel — set CONNECTOR=eDP-1 and retry"
    staged_param="drm.edid_firmware=$CONNECTOR:edid/hdr-patched-edid.bin"
fi
log_info "param: $staged_param"

if ! confirm "Remove the HDR EDID workaround (cmdline param + firmware + dracut hook)?"; then
    die "declined — nothing removed"
fi

# --- 1. cmdline param (grubby: BLS entries + grub config + kernel/cmdline) --
log_step "hdr: 1/3 kernel cmdline param (grubby)"
if command -v grubby >/dev/null 2>&1; then
    # Idempotent: a no-op when the param is already gone. Runs before the
    # firmware is deleted, so a failure here leaves a consistent state.
    run sudo grubby --remove-args="$staged_param"
    log_ok "param removed from BLS entries + bootloader configs"
else
    log_warn "grubby not found — the upstream seds cover limine/GRUB configs only"
    log_info "if this is a BLS system, remove the param from /boot/loader/entries/*.conf by hand"
fi

# --- 2. upstream uninstall (configs + firmware + dracut hook) --------------
log_step "hdr: 2/3 upstream uninstall"
run sudo bash "$UPSTREAM_UNINSTALL"

# --- 3. initramfs (upstream misses Fedora's tooling, same as install) ------
log_step "hdr: 3/3 initramfs"
if command -v dracut >/dev/null 2>&1; then
    log_info "rebuilding the initramfs without the EDID"
    run sudo dracut -f
else
    log_info "no dracut — the initramfs regenerates via mkinitcpio/limine above or at the next kernel update"
fi

# --- verify ----------------------------------------------------------------
echo
if [ "$DRY_RUN" = 1 ]; then
    log_info "dry-run: nothing was actually removed"
    exit 0
fi

verify_rc=0
if [ -f /usr/lib/firmware/edid/hdr-patched-edid.bin ]; then
    log_warn "firmware file still present: /usr/lib/firmware/edid/hdr-patched-edid.bin"
    verify_rc=1
fi
if grep -qF "$staged_param" /etc/default/grub /etc/kernel/cmdline /proc/cmdline 2>/dev/null; then
    log_warn "cmdline param still present somewhere — check: grubby --info=ALL | grep edid"
    verify_rc=1
fi
if [ "$verify_rc" -eq 0 ]; then
    log_ok "uninstall complete. Reboot to drop the param from the running kernel."
    log_info "reinstall: ./setup.sh hdr (see hdr/README.md for the Fedora/grubby finish)"
fi
exit "$verify_rc"
