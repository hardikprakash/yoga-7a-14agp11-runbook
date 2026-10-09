#!/usr/bin/env bash
# uninstall.sh — remove the Dolby tuning from this machine (either backend).
#
#   ./uninstall.sh                       remove whatever is staged
#   ./uninstall.sh --backend easyeffects only the EasyEffects route
#   ./uninstall.sh --backend pipewire    only the PipeWire filter-chain
#   ./uninstall.sh --dry-run              list what would go, delete nothing
#
# User-level only, no sudo: deletes files under $HOME, and (for the
# PipeWire route) restarts the user services to unload the chain.
# Does NOT uninstall the easyeffects package or the LV2 plugins — other
# things may use them. Reversible: just re-run ./install.sh afterwards.

set -euo pipefail
ROOT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib.sh
source "$ROOT_LIB/lib.sh"
# shellcheck source=audio_lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/audio_lib.sh"

usage() {
    cat <<EOF
audio module — remove the Dolby speaker tuning.

  ./uninstall.sh [--backend easyeffects|pipewire|all] [--dry-run] [--yes]

  easyeffects  deletes Dolby-*.json presets, Dolby-*.irs impulses, the
               speaker autoload entries and the tool's Nothing.json
               bypass preset (native + Flatpak locations)
  pipewire     deletes pipewire.conf.d/Dolby_*.conf + the .irs beside
               them, then restarts your user PipeWire to unload the chain
  all          (default) both

Nothing system-wide is touched. The easyeffects/LV2 packages stay
installed. To bring the tuning back: ./install.sh --backend <name>
EOF
}

BACKEND="all"
passthrough=()
while [ $# -gt 0 ]; do
    case "$1" in
        --backend)
            [ $# -ge 2 ] || die "--backend needs a value (easyeffects|pipewire|all)"
            BACKEND="$2"; shift 2 ;;
        --backend=*) BACKEND="${1#--backend=}"; shift ;;
        *) passthrough+=("$1"); shift ;;
    esac
done
parse_common_flags ${passthrough[@]+"${passthrough[@]}"}
refuse_root

if [ "$BACKEND" != all ]; then
    if ! normalized="$(audio_normalize_backend "$BACKEND")"; then
        die "unknown backend '$BACKEND' (easyeffects|pipewire|all)"
    fi
    BACKEND="$normalized"
fi

# ------------------------------------------------------------- easyeffects --
uninstall_easyeffects() {
    local dirs=("${AUDIO_EE_DIRS[@]}")
    local d f removed=0

    log_step "easyeffects route"
    for d in "${dirs[@]}"; do
        [ -d "$d" ] || continue

        # presets + impulses the converter generated
        for f in "$d"/output/Dolby-*.json "$d"/irs/Dolby-*.irs; do
            [ -e "$f" ] || continue
            log_info "remove $(realpath --relative-to="$HOME" "$f" 2>/dev/null || echo "$f")"
            run rm -f "$f"
            removed=$((removed + 1))
        done

        # autoload entries pointing at a Dolby preset (tolerate compact JSON)
        for f in "$d"/autoload/output/*.json; do
            [ -e "$f" ] || continue
            if grep -qE '"preset-name": *"Dolby-' "$f" 2>/dev/null; then
                log_info "remove autoload $(basename "$f")"
                run rm -f "$f"
                removed=$((removed + 1))
            fi
        done

        # the empty bypass preset — only when this tool wrote it
        # (tolerate compact and pretty JSON spacing)
        f="$d/output/Nothing.json"
        if [ -f "$f" ] && grep -q '"_generator"' "$f" 2>/dev/null &&
           grep -qE '"plugins_order": *\[\]' "$f" 2>/dev/null; then
            log_info "remove Nothing.json (tool-written bypass preset)"
            run rm -f "$f"
            removed=$((removed + 1))
        fi
    done

    if [ "$removed" -eq 0 ]; then
        log_ok "easyeffects route: nothing staged, nothing removed"
    elif [ "$DRY_RUN" = 1 ]; then
        log_ok "easyeffects route: would remove $removed file(s)"
    else
        log_ok "easyeffects route: removed $removed file(s)"
        log_info "in EasyEffects: turn the global Fallback Preset off"
        log_info "(preferences → autoload) if Nothing.json was in use"
    fi
    return 0
}

# ---------------------------------------------------------------- pipewire --
uninstall_pipewire() {
    local confs=() irs=() f removed=0

    log_step "pipewire route"
    for f in "$AUDIO_PW_DIR"/Dolby_*.conf; do
        [ -e "$f" ] && confs+=("$f")
    done
    for f in "$AUDIO_PW_DIR"/Dolby_*.irs; do
        [ -e "$f" ] && irs+=("$f")
    done

    if [ "${#confs[@]}" -eq 0 ] && [ "${#irs[@]}" -eq 0 ]; then
        log_ok "pipewire route: nothing staged, nothing removed"
        return 0
    fi

    for f in "${confs[@]}"; do
        log_info "remove $(realpath --relative-to="$HOME" "$f" 2>/dev/null || echo "$f")"
        run rm -f "$f"
        removed=$((removed + 1))
    done
    for f in "${irs[@]}"; do
        log_info "remove $(realpath --relative-to="$HOME" "$f" 2>/dev/null || echo "$f")"
        run rm -f "$f"
        removed=$((removed + 1))
    done

    if [ "$removed" -gt 0 ]; then
        if [ "$DRY_RUN" = 1 ]; then
            log_ok "pipewire route: would remove $removed file(s) + restart PipeWire"
        else
            log_info "restarting your user PipeWire to unload the chain"
            run systemctl --user restart pipewire pipewire-pulse
            sleep 1
            log_ok "pipewire route: removed $removed file(s), chain unloaded"
        fi
    fi
    return 0
}

# -------------------------------------------------------------------- main --
# Refuse to delete anything without an explicit yes (confirm() auto-answers
# in dry-run, and --yes skips it — which is how install.sh calls us when
# switching backends).
if ! confirm "Delete the staged '$BACKEND' Dolby route file(s)? (reinstall: ./install.sh --backend <name>)"; then
    die "declined — nothing removed"
fi

case "$BACKEND" in
    easyeffects) uninstall_easyeffects ;;
    pipewire)    uninstall_pipewire ;;
    all)         uninstall_easyeffects; uninstall_pipewire ;;
esac

echo
if [ "$DRY_RUN" = 1 ]; then
    log_info "dry-run: nothing was actually deleted"
else
    log_ok "uninstall complete. Reinstall any time: ./install.sh --backend <easyeffects|pipewire>"
fi
