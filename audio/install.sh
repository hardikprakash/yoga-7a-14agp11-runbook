#!/usr/bin/env bash
# install.sh — Dolby tuning via one of two backends (choose with --backend):
#
#   easyeffects (default)  → EasyEffects 8 presets + autoload (GUI, switchable)
#   pipewire              → a native PipeWire filter-chain conf (no GUI,
#                            ~3.5x less RAM, set-and-forget)
#
# Steps (user-level except package installs):
#   1. ensure the converter repo is cloned (gitignored in this runbook)
#   2. create/repair the repo-local venv (never touches system python)
#   3. install Python deps into that venv
#   4. backend dependencies (EasyEffects 8, or the LSP/Calf LV2 plugins)
#   5. generate from the bundled Windows XML, activate, and make sure the
#      *other* backend's files are gone (both chains must never run at once)

set -euo pipefail
# shellcheck source=../lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"
# shellcheck source=audio_lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/audio_lib.sh"

usage() {
    cat <<EOF
audio module — Dolby Atmos speaker tuning for Linux.

  ./install.sh [--backend easyeffects|pipewire] [--variant NAME]
               [--force] [--dry-run] [--yes]

  --backend easyeffects  EasyEffects 8 presets + autoload (default; GUI to
                         switch Dolby-Balanced/Detailed/Warm live)
  --backend pipewire     native PipeWire filter-chain, no GUI, no daemon
                         (activates Balanced; other voicings: see --variant)
  ee / pw                accepted as short aliases
  --variant balanced|detailed|warm|all
                         pipewire only: which voicing to convert (default
                         balanced; 'all' needs --target-sink semantics the
                         runbook doesn't set — use balanced/detailed/warm)
  --force                pipewire only: overwrite an existing Dolby_*.conf
                         + .irs instead of the converter refusing

  1. clones antoinecellerier/speaker-tuning-to-easyeffects if absent
  2. creates/repairs .venv inside the repo (no system python packages)
  3. pip-installs numpy/scipy/etc. into that venv
  4. installs the backend's dependencies:
       easyeffects → EasyEffects 8 (distro package or Flatpak hint)
       pipewire    → LSP + Calf LV2 plugins + lilv (auto) AND the PipeWire
                     LV2 filter loader (libspa-filter-graph-plugin-lv2.so),
                     which some distros split out — without it the chain
                     silently fails to load
  5. runs the converter against the bundled XML and activates it; staged
     files of the *other* backend are removed first (prompted), because
     both chains processing the same audio sounds wrong

Switch backend later:  ./install.sh --backend <other>
Remove everything:     ./uninstall.sh
Verify:                ./check.sh
EOF
}

# --backend/--variant/--force come before parse_common_flags (which
# rejects anything it does not know).
BACKEND="easyeffects"
VARIANT=""
FORCE=0
passthrough=()
while [ $# -gt 0 ]; do
    case "$1" in
        --backend)
            [ $# -ge 2 ] || die "--backend needs a value (easyeffects|pipewire)"
            BACKEND="$2"; shift 2 ;;
        --backend=*) BACKEND="${1#--backend=}"; shift ;;
        --variant)
            [ $# -ge 2 ] || die "--variant needs a value (balanced|detailed|warm|all)"
            VARIANT="$2"; shift 2 ;;
        --variant=*) VARIANT="${1#--variant=}"; shift ;;
        --force) FORCE=1; shift ;;
        *) passthrough+=("$1"); shift ;;
    esac
done
parse_common_flags ${passthrough[@]+"${passthrough[@]}"}
refuse_root

if ! normalized="$(audio_normalize_backend "$BACKEND")"; then
    die "unknown backend '$BACKEND' (easyeffects|pipewire — aliases: ee, pw)"
fi
BACKEND="$normalized"
if [ -n "$VARIANT" ]; then
    case "$VARIANT" in
        balanced|detailed|warm) ;;
        all)
            die "--variant all installs several chains and needs --target-sink '' + smart-filter routing off — not automated here; run the converter by hand, see audio/README.md" ;;
        *) die "unknown variant '$VARIANT' (balanced|detailed|warm)" ;;
    esac
fi
if [ "$FORCE" = 1 ] && [ "$BACKEND" != pipewire ]; then
    log_warn "--force is only meaningful for the pipewire backend (the easyeffects converter overwrites silently) — ignoring it"
    FORCE=0
fi

REPO="$RUNBOOK_ROOT/audio/speaker-tuning-to-easyeffects"
REPO_URL="https://github.com/antoinecellerier/speaker-tuning-to-easyeffects.git"
VENV="$REPO/.venv"
XML_DIR="$RUNBOOK_ROOT/audio/xml"
# Exact match for this machine's codec subsystem (ALC287, 17AA:3957).
XML_GLOB="DEV_0287_SUBSYS_17AA3957*.xml"

log_info "backend: $BACKEND${VARIANT:+ (variant: $VARIANT)}"

# ------------------------------------------------------------- 1. clone ----
log_step "audio: 1/5 converter repo"
if [ -d "$REPO/.git" ]; then
    log_ok "already cloned: $REPO"
elif [ -d "$REPO" ]; then
    die "$REPO exists but is not a git repo — remove it and re-run"
else
    require_cmd git "to clone the converter"
    run git clone "$REPO_URL" "$REPO"
    log_ok "cloned"
fi

# ------------------------------------------------- 2. venv create/repair ----
log_step "audio: 2/5 python venv"
require_cmd python3 "for the converter venv"

venv_ok=0
if [ -x "$VENV/bin/python" ] && "$VENV/bin/python" -c 'import sys' 2>/dev/null; then
    # venvs embed absolute paths at creation time (bin/activate, pyvenv.cfg);
    # a moved repo leaves those stale even though bin/python still resolves.
    # activate writes VIRTUAL_ENV unquoted (py>=3.14) or single-quoted.
    if grep -qF "VIRTUAL_ENV=$VENV" "$VENV/bin/activate" 2>/dev/null ||
       grep -qF "VIRTUAL_ENV='$VENV'" "$VENV/bin/activate" 2>/dev/null; then
        venv_ok=1
    else
        log_warn "venv was created at a different path — recreating"
    fi
else
    log_warn "venv missing or broken — creating"
fi

if [ "$venv_ok" = 0 ]; then
    run rm -rf "$VENV"
    run python3 -m venv "$VENV"
    log_ok "venv created: $VENV"
else
    log_ok "venv reusable: $VENV"
fi

# ------------------------------------------------------------- 3. deps -----
log_step "audio: 3/5 python dependencies"
if "$VENV/bin/python" -c 'import numpy, scipy' 2>/dev/null; then
    log_ok "numpy + scipy already present"
else
    run "$VENV/bin/python" -m pip install --quiet --upgrade pip
    run "$VENV/bin/python" -m pip install --quiet -r "$REPO/requirements.txt"
    log_ok "requirements installed into the venv"
fi

# ------------------------------------------------- 4. backend dependencies --
log_step "audio: 4/5 dependencies for backend '$BACKEND'"

# True if an LV2 bundle exists anywhere a distro puts them.
lv2_bundle_present() {
    local bundle="$1" d
    for d in /usr/lib64/lv2 "/usr/lib/lv2" /usr/lib/*/lv2; do
        if [ -d "$d/$bundle" ]; then
            return 0
        fi
    done
    return 1
}

if [ "$BACKEND" = easyeffects ]; then
    ee_bin=""
    if command -v easyeffects >/dev/null 2>&1; then
        ee_bin="$(command -v easyeffects)"
    elif command -v flatpak >/dev/null 2>&1 && flatpak info com.github.wwmm.easyeffects >/dev/null 2>&1; then
        ee_bin="flatpak run com.github.wwmm.easyeffects"
    fi

    if [ -n "$ee_bin" ]; then
        ee_ver="$($ee_bin --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1 || true)"
        ee_major="${ee_ver%%.*}"
        if [ -n "$ee_major" ] && [ "$ee_major" -ge 8 ] 2>/dev/null; then
            log_ok "EasyEffects $ee_ver ($ee_bin)"
        else
            log_warn "EasyEffects ${ee_ver:-unknown} is too old — presets need 8.x"
            log_info "install the Flatpak instead: flatpak install flathub com.github.wwmm.easyeffects"
        fi
    else
        local_pkgs=()
        case "$(pkg_manager)" in
            dnf|apt|pacman|zypper) local_pkgs=(easyeffects) ;;
            *) log_warn "no supported package manager; install EasyEffects 8 yourself (e.g. Flatpak)" ;;
        esac
        if [ "${#local_pkgs[@]}" -gt 0 ]; then
            pkg_install "${local_pkgs[@]}" || true
        fi
        if command -v easyeffects >/dev/null 2>&1; then
            log_ok "EasyEffects installed"
        else
            log_warn "EasyEffects not on PATH yet — presets are generated anyway,"
            log_info "install it before they can be used: flatpak install flathub com.github.wwmm.easyeffects"
        fi
    fi
else
    # pipewire route: the filter-chain loads LV2 plugins from the system.
    # LSP = PEQ/MBC/regulator/limiter, Calf = bass enhancer/stereo tools
    # (upstream docs "Plugin dependencies and validation"); lilv ships
    # lv2info, which makes the converter validate before it writes.
    pkgs=()
    calf_note=""
    case "$(pkg_manager)" in
        dnf)     pkgs=(lsp-plugins-lv2 lv2-calf-plugins lilv) ;;
        apt)     pkgs=(lsp-plugins-lv2 calf-plugins lilv-utils) ;;
        pacman)  pkgs=(lsp-plugins-lv2 calf lilv-tools) ;;
        zypper)
            pkgs=(lv2-lsp-plugins lilv)
            calf_note="openSUSE: Calf comes from Packman, not the main repo — install it if the converter asks"
            ;;
        *)       log_warn "no supported package manager; install LSP + Calf LV2 plugins yourself (see audio/README.md)" ;;
    esac

    missing=()
    for p in ${pkgs[@]+"${pkgs[@]}"}; do
        pkg_installed "$p" || missing+=("$p")
    done
    if [ "${#missing[@]}" -gt 0 ]; then
        log_info "missing LV2 dependencies: ${missing[*]}"
        if ! pkg_install "${missing[@]}"; then
            die "declined — the PipeWire filter-chain cannot load without its LV2 plugins"
        fi
    else
        log_ok "LV2 dependencies present: ${pkgs[*]}"
    fi
    [ -n "$calf_note" ] && log_info "$calf_note"

    # pw-dump resolves the speaker sink (Fedora/openSUSE/Alpine split it out
    # into its own package; elsewhere it ships with the daemon).
    if ! command -v pw-dump >/dev/null 2>&1; then
        if [ "$(pkg_manager)" = dnf ]; then
            pkg_install pipewire-utils || log_warn "pw-dump missing — sink auto-detection will fail"
        else
            log_warn "pw-dump missing — install your PipeWire CLI tools (the converter names the package)"
        fi
    else
        log_ok "pw-dump present"
    fi

    # Fast existence check; the converter re-validates properly via lv2info.
    if lv2_bundle_present lsp-plugins.lv2; then
        log_ok "lsp-plugins.lv2 bundle found"
    else
        log_warn "lsp-plugins.lv2 not found yet — the converter will report if it is truly missing"
    fi

    # The LV2 *loader* is a different thing from the bundles above: without
    # it PipeWire parses the conf, then silently discards every lv2 node and
    # the sink never appears (journal: "can't load plugin type 'lv2'"). The
    # converter's own doctor checks bundles only, so it cannot catch this.
    if audio_pw_loader_present; then
        log_ok "PipeWire LV2 filter loader present (libspa-filter-graph-plugin-lv2.so)"
    else
        loader_pkg="$(audio_pw_loader_pkg)"
        if [ -n "$loader_pkg" ]; then
            log_warn "PipeWire cannot load LV2 filter-chains: the lv2 loader plugin is missing"
            log_info "some distros split it out (Fedora: pipewire-module-filter-chain-lv2)"
            if pkg_install "$loader_pkg"; then
                if audio_pw_loader_present; then
                    log_ok "loader installed: $loader_pkg"
                else
                    log_warn "package installed but loader .so still not found — search for the package providing"
                    log_info "  libspa-filter-graph-plugin-lv2.so  (dnf provides 'libspa*lv2*' / apt-file search)"
                    log_info "without it the chain will fail to load: sink 'Dolby_*' never appears"
                fi
            else
                log_warn "skipped — the filter-chain will NOT load without the loader"
                log_info "install it later: ./setup.sh audio --backend pipewire"
            fi
        else
            log_warn "PipeWire LV2 loader .so not found; install the package providing it (see audio/README.md)"
        fi
    fi
fi

# ------------------------------ interstitial: deactivate the other backend --
# Not a numbered step: only runs when the other backend's files are staged.
# Only one chain may process the speaker output. Staged files of the other
# backend are removed here (after an explicit prompt); declining keeps them
# but is loud about the consequence.
OTHER=""
if [ "$BACKEND" = pipewire ] && audio_ee_route_staged; then
    OTHER=easyeffects
elif [ "$BACKEND" = easyeffects ] && audio_pw_route_staged; then
    OTHER=pipewire
fi

if [ -n "$OTHER" ]; then
    log_step "audio: switching backend ($OTHER → $BACKEND)"
    other_flags=(--backend "$OTHER" --yes)
    [ "$DRY_RUN" = 1 ] && other_flags+=(--dry-run)
    if confirm "A staged '$OTHER' route was found — remove it? (both must never run at once)"; then
        bash "$RUNBOOK_ROOT/audio/uninstall.sh" "${other_flags[@]}"
        if [ "$DRY_RUN" = 1 ]; then
            log_ok "would remove the $OTHER route (dry-run)"
        else
            log_ok "removed the $OTHER route"
        fi
    else
        log_warn "kept the $OTHER route — if it activates too, audio is processed TWICE"
        if [ "$BACKEND" = pipewire ]; then
            log_info "disable it now: EasyEffects → preferences → Background Service OFF,"
            log_info "and delete its autoload (or: ./uninstall.sh --backend easyeffects)"
        else
            log_info "unload it now: ./uninstall.sh --backend pipewire"
        fi
    fi
fi
if [ "$BACKEND" = pipewire ] && audio_ee_route_active; then
    log_warn "EasyEffects is currently running — quit it (or turn off Background Service)"
    log_info "or the Dolby chain will process the same audio twice"
fi

# ------------------------------------------------------- 5. converter ------
log_step "audio: 5/5 generate + activate from the bundled Windows XML"
mapfile -t xmls < <(compgen -G "$XML_DIR/$XML_GLOB" || true)
if [ "${#xmls[@]}" -eq 0 ]; then
    mapfile -t xmls < <(compgen -G "$XML_DIR"/*.xml || true)
fi
[ "${#xmls[@]}" -gt 0 ] || die "no tuning XML found in $XML_DIR"
if [ "${#xmls[@]}" -gt 1 ]; then
    log_info "multiple XMLs found, using exact subsystem match: ${xmls[0]}"
fi

if [ "$BACKEND" = easyeffects ]; then
    run "$VENV/bin/python" "$REPO/dolby_to_easyeffects.py" "${xmls[0]}" --autoload

    echo
    log_ok "presets generated. To keep them after reboot:"
    printf '    EasyEffects → preferences → enable Background Service + Autostart\n'
    log_info "sound wrong? run the doctor: $VENV/bin/python $REPO/dolby_to_easyeffects.py --doctor"
else
    variant_args=()
    [ -n "$VARIANT" ] && variant_args=(--variant "$VARIANT")

    # Fail fast: without --force the converter generates everything, then
    # refuses at the very end because the conf exists — a wasted ~30s run.
    # Name rule (from the tool): preset Dolby-Balanced → conf Dolby_Balanced.
    vname="${VARIANT:-balanced}"
    conf_name="Dolby_$(tr '[:lower:]' '[:upper:]' <<<"${vname:0:1}")${vname:1}"
    if [ "$FORCE" = 0 ] && [ -f "$AUDIO_PW_DIR/$conf_name.conf" ]; then
        if [ "$DRY_RUN" = 1 ]; then
            log_warn "$conf_name.conf exists — the real run would stop here; pass --force to overwrite"
        else
            die "$AUDIO_PW_DIR/$conf_name.conf exists — pass --force to overwrite, or remove it first: ./setup.sh audio --uninstall --backend pipewire"
        fi
    fi
    [ "$FORCE" = 1 ] && variant_args+=(--force)

    log_info "activating: the converter restarts your user PipeWire (audio pauses ~1s)"
    run "$VENV/bin/python" "$REPO/dolby_to_pipewire.py" "${xmls[0]}" \
        ${variant_args[@]+"${variant_args[@]}"}

    echo
    log_ok "PipeWire filter-chain installed and loaded."
    log_info "switch voicing later: ./install.sh --backend pipewire --variant detailed|warm"
    log_info "sound wrong? run the doctor: $VENV/bin/python $REPO/dolby_to_pipewire.py --doctor"
fi
