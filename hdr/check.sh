#!/usr/bin/env bash
# check.sh — read-only status of the hdr module.
#
# Probes, without touching anything:
#   * libdisplay-info version (0.3.0 → the DisplayID bug applies to you)
#   * patched EDID installed in /usr/lib/firmware/edid?
#   * drm.edid_firmware= on the kernel command line / bootloader config?
#   * HDR metadata visible to libdisplay-info right now?
#
# For the full 5-step chain walk (EDID → infoframe → panel) run the
# vendored tool afterwards:  hdr/hdr-edid-fix/check.sh

set -euo pipefail
# shellcheck source=../lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

FIX="$RUNBOOK_ROOT/hdr/hdr-edid-fix"
FW_NAME="hdr-patched-edid.bin"
FW_PATH="/usr/lib/firmware/edid/$FW_NAME"

if [ ! -d "$FIX" ]; then
    chk_fail "hdr-edid-fix not cloned"
    chk_info "run ./setup.sh hdr (clone step) or: git clone https://github.com/Boogie61/hdr-edid-fix.git $FIX"
    exit 1
fi

# --- libdisplay-info version: decides whether problem 1 even applies ----
ldi_ver="$(rpm -q --qf '%{VERSION}\n' libdisplay-info 2>/dev/null | head -n1 || true)"
if [ -z "$ldi_ver" ] && command -v dpkg-query >/dev/null 2>&1; then
    ldi_ver="$(dpkg-query -W -f='${Version}\n' libdisplay-info0 2>/dev/null || true)"
fi
if [ -z "$ldi_ver" ] && command -v pacman >/dev/null 2>&1; then
    ldi_ver="$(pacman -Q libdisplay-info 2>/dev/null | awk '{print $2}' || true)"
fi

needs_edid_fix=0
if [ -z "$ldi_ver" ]; then
    chk_warn "libdisplay-info version unknown (package query failed)"
elif [ "$(printf '%s\n' "$ldi_ver" 0.4.0 | sort -V | head -n1)" = "0.4.0" ]; then
    chk_ok "libdisplay-info $ldi_ver ≥ 0.4.0 — DisplayID bug fixed upstream, no EDID patch needed"
else
    needs_edid_fix=1
    chk_warn "libdisplay-info $ldi_ver < 0.4.0 — HDR metadata hidden in DisplayID is invisible"
fi

# --- is the patched EDID in place? ---------------------------------------
patched=0
if [ -f "$FW_PATH" ]; then
    patched=1
    chk_ok "patched EDID installed: $FW_PATH ($(wc -c <"$FW_PATH") bytes)"
fi

# Three places the param can live, and they mean different things:
#   /proc/cmdline          → ACTIVE on the running kernel
#   config files + grubby  → STAGED, pending (re)generation and/or reboot
# grubby --info needs root on BLS systems (/boot/loader/entries is 700), so
# the config files are the root-free staged check; grubby is a last resort.
cmdline_hit=0
cmdline_staged=0
if grep -q "drm.edid_firmware=.*$FW_NAME" /proc/cmdline 2>/dev/null; then
    cmdline_hit=1
    chk_ok "kernel command line carries drm.edid_firmware=...$FW_NAME"
fi
if [ "$cmdline_hit" = 0 ]; then
    for f in /etc/default/grub /etc/kernel/cmdline /etc/default/limine; do
        if grep -q "drm.edid_firmware=.*$FW_NAME" "$f" 2>/dev/null; then
            cmdline_staged=1
            chk_ok "param staged in $f — active after bootloader regen + reboot"
        fi
    done
fi
if [ "$cmdline_hit" = 0 ] && [ "$cmdline_staged" = 0 ] &&
   command -v grubby >/dev/null 2>&1 &&
   grubby --info=ALL 2>/dev/null | grep -q "drm.edid_firmware=.*$FW_NAME"; then
    cmdline_staged=1
    chk_ok "param staged via grubby (BLS) — active after reboot"
fi

# --- verdict ---------------------------------------------------------------
# Half-installed / half-removed state: the cmdline asks for a firmware
# file that no longer exists. Happens when the upstream uninstall.sh ran
# on a BLS system (it seds the configs but misses /boot/loader/entries —
# see issue Boogie61/hdr-edid-fix#1). Every boot then requests a missing
# file; the kernel falls back to the unpatched EDID, so the HDR switch
# disappears again. Fix: ./setup.sh hdr --uninstall (removes the param
# everywhere), then reinstall from scratch.
if [ "$patched" = 0 ] && { [ "$cmdline_hit" = 1 ] || [ "$cmdline_staged" = 1 ]; }; then
    chk_fail "cmdline asks for the patched EDID but the firmware file is missing"
    chk_info "the kernel falls back to the unpatched EDID (HDR switch gone again)"
    chk_info "finish the removal first: ./setup.sh hdr --uninstall"
    chk_info "then reinstall: ./setup.sh hdr + the Fedora/grubby finish in hdr/README.md"
    exit 1
fi

if [ "$needs_edid_fix" = 1 ]; then
    if [ "$patched" = 1 ] && { [ "$cmdline_hit" = 1 ] || [ "$cmdline_staged" = 1 ]; }; then
        chk_ok "EDID workaround active — problem 1 covered"
        [ "$cmdline_hit" = 0 ] && chk_info "staged but not live yet: reboot once to activate"
        # Fedora: the initramfs must carry the file (DRM loads from it);
        # the dracut conf is the hook that puts it there.
        if [ -f /etc/dracut.conf.d/90-hdr-edid.conf ] ||
           grep -q "$FW_PATH" /etc/dracut.conf.d/*.conf /etc/dracut.conf 2>/dev/null; then
            chk_ok "dracut hook present (file will be in every initramfs)"
        elif [ "$(pkg_manager 2>/dev/null)" = dnf ] || command -v dracut >/dev/null 2>&1; then
            chk_warn "no dracut hook — the initramfs may lack the EDID (DRM loads early)"
            chk_info "re-run: cd hdr/hdr-edid-fix && sudo ./install.sh (its dracut step worked)"
        fi
        chk_info "full chain walk: hdr/hdr-edid-fix/check.sh (after enabling HDR)"
    else
        chk_fail "HDR switch will be missing: fix not installed yet"
        chk_info "./setup.sh hdr prints the guided steps (never automated: bootloader + initramfs)"
        chk_info "preview safely first: hdr/hdr-edid-fix/edid/patch-edid.py --check"
        chk_info "Fedora note: the upstream installer cannot edit grubby/BLS — see hdr/README.md"
    fi
elif [ "$patched" = 0 ]; then
    chk_ok "no EDID patch needed on this libdisplay-info"
    chk_info "if an old patch was installed before, remove it: sudo hdr/hdr-edid-fix/uninstall.sh"
fi

# --- problem 2: mutter's empty HDR mastering metadata ----------------------
if pgrep -x gnome-shell >/dev/null 2>&1; then
    if grep -rq "hdr-mastering-metadata" /usr/share/doc/mutter*/ 2>/dev/null; then
        chk_info "mutter: modified build detected (mastering-metadata patch may be applied)"
    else
        modified="$(rpm -V mutter 2>/dev/null)" || true
        if grep -q "^..[mc]" <<<"$modified"; then
            chk_info "mutter: modified build detected (mastering-metadata patch may be applied)"
        else
            chk_warn "mutter: HDR on but washed out? stock mutter sends empty mastering metadata"
            chk_info "details + patch: hdr/README.md (problem 2) — optional, cosmetics only"
        fi
    fi
    chk_info "verify what mutter programs: hdr/hdr-edid-fix/infoframe.sh (HDR on)"
fi
