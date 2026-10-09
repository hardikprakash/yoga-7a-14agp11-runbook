#!/usr/bin/env bash
# check.sh — read-only status of the audio module.
# Probes: repo cloned? venv healthy? presets generated? EasyEffects 8 present?

set -euo pipefail
# shellcheck source=../lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

REPO="$RUNBOOK_ROOT/audio/speaker-tuning-to-easyeffects"
VENV="$REPO/.venv"
PRESET_DIR="$HOME/.local/share/easyeffects/output"
PRESET_FLATPAK_DIR="$HOME/.var/app/com.github.wwmm.easyeffects/config/easyeffects/output"

# --- converter repo ---
if [ ! -d "$REPO/.git" ]; then
    chk_fail "converter repo not cloned"
    chk_info "run ./setup.sh audio"
    exit 1
fi

# --- venv ---
if [ ! -x "$VENV/bin/python" ] || ! "$VENV/bin/python" -c 'import numpy, scipy' 2>/dev/null; then
    chk_warn "venv missing or lacks numpy/scipy"
    chk_info "run ./setup.sh audio (creates/repairs the repo-local venv)"
else
    chk_ok "converter repo + venv ready"
fi

# --- presets ---
presets=()
for d in "$PRESET_DIR" "$PRESET_FLATPAK_DIR"; do
    while IFS= read -r f; do
        presets+=("$(basename "$f" .json)")
    done < <(compgen -G "$d/Dolby-*.json" || true)
done

if [ "${#presets[@]}" -eq 0 ]; then
    chk_warn "no Dolby presets generated yet"
    chk_info "run ./setup.sh audio"
else
    chk_ok "${#presets[@]} presets: ${presets[*]}"
fi

# --- autoload (applies the preset to the internal speakers automatically) ---
if compgen -G "$HOME/.local/share/easyeffects/autoload/output/*.json" >/dev/null 2>&1; then
    chk_ok "autoload configured for the speaker sink"
else
    chk_warn "no autoload — the preset must be picked manually in EasyEffects"
    chk_info "re-run the converter with --autoload, see audio/README.md"
fi

# --- EasyEffects itself ---
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
    chk_warn "EasyEffects not installed — presets exist but cannot run"
    chk_info "run ./setup.sh audio, or: flatpak install flathub com.github.wwmm.easyeffects"
fi

# --- autostart hint (GUI toggle, cannot be checked reliably from here) ---
chk_info "make it persist: EasyEffects → preferences → Background Service + Autostart"
