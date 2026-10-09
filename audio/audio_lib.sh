#!/usr/bin/env bash
# audio_lib.sh — shared route detection for the audio module.
# Source AFTER ../lib.sh. Read-only: these helpers only look at files,
# they never write. Call them inside `if` / `||` / `&&` (never bare —
# under `set -e` a bare non-zero return would abort the caller).
#
# Two backends can stage the Dolby tuning on this machine:
#   easyeffects → presets + impulses + autoload under an easyeffects dir
#   pipewire    → a filter-chain conf in pipewire.conf.d/
# Only one should be active: both chains would process the same audio.

# Where each backend's files live (native + Flatpak EasyEffects).
AUDIO_EE_DIRS=(
    "${XDG_DATA_HOME:-$HOME/.local/share}/easyeffects"
    "$HOME/.var/app/com.github.wwmm.easyeffects/data/easyeffects"
    "$HOME/.var/app/com.github.wwmm.easyeffects/config/easyeffects"
)
AUDIO_PW_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/pipewire/pipewire.conf.d"

# Canonical backend names; accepts the ee/pw short aliases.
audio_normalize_backend() {
    case "$1" in
        easyeffects|ee) printf 'easyeffects\n' ;;
        pipewire|pw)    printf 'pipewire\n' ;;
        *)              return 1 ;;
    esac
}

# True if any EasyEffects route files are staged (presets/impulses).
audio_ee_route_staged() {
    local d
    for d in "${AUDIO_EE_DIRS[@]}"; do
        if compgen -G "$d/output/Dolby-*.json" >/dev/null 2>&1; then
            return 0
        fi
    done
    return 1
}

# True if a speaker autoload entry pointing at a Dolby preset is staged.
audio_ee_autoload_present() {
    local d f
    for d in "${AUDIO_EE_DIRS[@]}"; do
        for f in "$d"/autoload/output/*.json; do
            [ -e "$f" ] || continue
            # tolerate both compact and pretty JSON (":" vs ": ")
            if grep -qE '"preset-name": *"Dolby-' "$f" 2>/dev/null; then
                return 0
            fi
        done
    done
    return 1
}

# Count staged Dolby presets across all EasyEffects dirs (echoes a number).
audio_ee_preset_count() {
    local d n=0 f
    for d in "${AUDIO_EE_DIRS[@]}"; do
        for f in "$d"/output/Dolby-*.json; do
            [ -e "$f" ] || continue
            n=$((n + 1))
        done
    done
    printf '%s\n' "$n"
}

# True if a PipeWire filter-chain conf from this tool is staged.
audio_pw_route_staged() {
    if compgen -G "$AUDIO_PW_DIR/Dolby_*.conf" >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

# True if a Dolby filter-chain is actually loaded in the running graph.
audio_pw_route_active() {
    if ! command -v pw-dump >/dev/null 2>&1; then
        return 1
    fi
    if pw-dump 2>/dev/null | grep -q 'effect_input\.Dolby'; then
        return 0
    fi
    return 1
}

# True if an EasyEffects process is running (native or Flatpak).
audio_ee_route_active() {
    if pgrep -x easyeffects >/dev/null 2>&1 ||
       pgrep -f 'com.github.wwmm.easyeffects' >/dev/null 2>&1; then
        return 0
    fi
    return 1
}
