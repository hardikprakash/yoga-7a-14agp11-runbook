#!/usr/bin/env bash
# check.sh — read-only status of the audio module (both backends).
# Reports what is staged, what is active, and refuses to stay quiet
# when both routes are present (they must never process audio at once).

set -euo pipefail
# shellcheck source=../lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"
# shellcheck source=audio_lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/audio_lib.sh"

REPO="$RUNBOOK_ROOT/audio/speaker-tuning-to-easyeffects"
VENV="$REPO/.venv"

# --- converter repo + venv (needed to regenerate for either backend) -------
if [ ! -d "$REPO/.git" ]; then
    chk_fail "converter repo not cloned"
    chk_info "run ./setup.sh audio"
    exit 1
fi
if [ ! -x "$VENV/bin/python" ] || ! "$VENV/bin/python" -c 'import numpy, scipy' 2>/dev/null; then
    chk_warn "venv missing or lacks numpy/scipy"
    chk_info "run ./setup.sh audio (creates/repairs the repo-local venv)"
else
    chk_ok "converter repo + venv ready"
fi

# --- what is staged ---------------------------------------------------------
ee_staged=0 pw_staged=0
audio_ee_route_staged && ee_staged=1
audio_pw_route_staged && pw_staged=1

if [ "$ee_staged" = 1 ] && [ "$pw_staged" = 1 ]; then
    chk_fail "both routes staged: easyeffects + pipewire — remove one, both must never run at once"
    chk_info "keep pipewire: ./setup.sh audio --uninstall --backend easyeffects"
    chk_info "keep easyeffects: ./setup.sh audio --uninstall --backend pipewire"
    chk_info "or switch cleanly: ./setup.sh audio --backend <one of them> (removes the other)"
    exit 1
fi

if [ "$ee_staged" = 1 ]; then
    # --- EasyEffects route details -----------------------------------------
    ee_preset_count="$(audio_ee_preset_count)"
    if audio_ee_autoload_present; then
        chk_ok "easyeffects route: $ee_preset_count presets + speaker autoload"
    else
        chk_warn "easyeffects route: $ee_preset_count presets, but no speaker autoload"
        chk_info "re-run the converter with --autoload, see audio/README.md"
    fi

    if command -v easyeffects >/dev/null 2>&1; then
        ee_ver="$(easyeffects --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -n1 || true)"
        ee_major="${ee_ver%%.*}"
        if [ -n "$ee_major" ] && [ "$ee_major" -ge 8 ] 2>/dev/null; then
            chk_ok "EasyEffects $ee_ver (native)"
        else
            chk_warn "EasyEffects ${ee_ver:-unknown} installed, but 8.x is required"
            chk_info "flatpak install flathub com.github.wwmm.easyeffects"
        fi
    elif command -v flatpak >/dev/null 2>&1 && flatpak info com.github.wwmm.easyeffects >/dev/null 2>&1; then
        chk_ok "EasyEffects (Flatpak)"
    else
        chk_warn "presets staged but EasyEffects not installed — they cannot run"
        chk_info "run ./setup.sh audio --backend easyeffects, or: flatpak install flathub com.github.wwmm.easyeffects"
    fi

    if audio_ee_route_active; then
        chk_ok "EasyEffects is running (chain live)"
    else
        chk_info "EasyEffects not running — enable Background Service + Autostart in its preferences"
    fi
    chk_info "switch voicing in the EasyEffects GUI (Balanced/Detailed/Warm)"

elif [ "$pw_staged" = 1 ]; then
    # --- PipeWire route details ---------------------------------------------
    conf_count=0
    while IFS= read -r _; do
        conf_count=$((conf_count + 1))
    done < <(compgen -G "$AUDIO_PW_DIR/Dolby_*.conf" || true)
    chk_ok "pipewire route: $conf_count filter-chain conf(s) staged in ${AUDIO_PW_DIR#"$HOME"}/"

    if audio_pw_route_active; then
        chk_ok "filter-chain loaded in PipeWire (no GUI, no daemon needed)"
    else
        chk_warn "staged but NOT loaded — re-run ./setup.sh audio --backend pipewire (it restarts PipeWire)"
        chk_info "or restart manually: systemctl --user restart pipewire pipewire-pulse"
    fi

    if audio_ee_route_active; then
        chk_warn "EasyEffects is also running — audio would be processed TWICE"
        chk_info "quit it, or its Background Service, now"
    fi
    chk_info "change voicing: ./setup.sh audio --backend pipewire --variant detailed|warm"

else
    chk_fail "no route installed — nothing applies the Dolby tuning"
    chk_info "run ./setup.sh audio            (EasyEffects backend, default)"
    chk_info "        ./setup.sh audio --backend pipewire   (native, no GUI)"
    exit 1
fi

exit 0
