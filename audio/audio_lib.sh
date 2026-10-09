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
    # Capture first, then grep: `pw-dump | grep -q` under `set -o pipefail`
    # fails whenever grep -q exits early (SIGPIPE → pw-dump rc 141), even on
    # a match — a match would then read as "not active".
    local dump
    dump="$(pw-dump 2>/dev/null)" || true
    if grep -q 'effect_input\.Dolby' <<<"$dump"; then
        return 0
    fi
    return 1
}

# True if PipeWire can parse type="lv2" filter-chain nodes at all.
# This is the *loader* (spa.filter-graph plugin), NOT the LSP/Calf bundles:
# without it every conf with lv2 nodes is silently discarded at load and the
# sink never appears (journal: "can't load plugin type 'lv2'"). Distros split
# it out: Fedora pipewire-module-filter-chain-lv2, Ubuntu
# libspa-0.2-modules-extra, Debian libspa-0.2-modules, openSUSE
# pipewire-spa-plugins-0_2. AUDIO_SPA_FG_DIRS overrides the search dirs
# (used by tests to simulate a missing loader).
audio_pw_loader_present() {
    local d
    if [ -n "${AUDIO_SPA_FG_DIRS:-}" ]; then
        for d in $AUDIO_SPA_FG_DIRS; do
            if [ -f "$d/libspa-filter-graph-plugin-lv2.so" ]; then
                return 0
            fi
        done
        return 1
    fi
    for d in /usr/lib64/spa-0.2/filter-graph /usr/lib/spa-0.2/filter-graph \
             /usr/lib/*/spa-0.2/filter-graph; do
        if [ -f "$d/libspa-filter-graph-plugin-lv2.so" ]; then
            return 0
        fi
    done
    # pre-1.2 layout: the LV2 support was a pipewire module, not a spa plugin
    for d in /usr/lib64/pipewire-0.3 /usr/lib/pipewire-0.3 /usr/lib/*/pipewire-0.3; do
        if [ -f "$d/libpipewire-module-filter-chain-lv2.so" ]; then
            return 0
        fi
    done
    return 1
}

# Distro package that provides the LV2 loader (best effort; the caller
# re-checks the .so afterwards and guides the user if the mapping missed).
audio_pw_loader_pkg() {
    case "$(pkg_manager)" in
        dnf)    printf 'pipewire-module-filter-chain-lv2\n' ;;
        apt)    # Ubuntu ships lv2 in -extra; Debian folds it into the base
                # modules package. Ask apt which name it actually knows.
                if command -v apt-cache >/dev/null 2>&1 &&
                   apt-cache show libspa-0.2-modules-extra >/dev/null 2>&1; then
                    printf 'libspa-0.2-modules-extra\n'
                else
                    printf 'libspa-0.2-modules\n'
                fi ;;
        pacman) printf 'libspa-0.2\n' ;;
        zypper) printf 'pipewire-spa-plugins-0_2\n' ;;
        *)      printf '\n' ;;
    esac
}

# True if an EasyEffects process is running (native or Flatpak).
audio_ee_route_active() {
    if pgrep -x easyeffects >/dev/null 2>&1 ||
       pgrep -f 'com.github.wwmm.easyeffects' >/dev/null 2>&1; then
        return 0
    fi
    return 1
}
