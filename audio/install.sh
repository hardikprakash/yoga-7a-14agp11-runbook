#!/usr/bin/env bash
# install.sh — EasyEffects 8 + the Dolby → EasyEffects converter pipeline.
#
# Steps (all user-level except the EasyEffects package install):
#   1. ensure the converter repo is cloned (gitignored in this runbook)
#   2. create/repair the repo-local venv (never touches system python)
#   3. install Python deps into that venv
#   4. install EasyEffects 8 (native package if the distro ships 8.x)
#   5. generate presets from the bundled Windows XML + set up autoload

set -euo pipefail
# shellcheck source=../lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

usage() {
    cat <<EOF
audio module — Dolby Atmos speaker tuning for Linux.

  ./install.sh [--dry-run] [--yes]

  1. clones antoinecellerier/speaker-tuning-to-easyeffects if absent
  2. creates/repair .venv inside the repo (no system python packages)
  3. pip-installs numpy/scipy/etc. into that venv
  4. installs EasyEffects 8 via the distro package manager
  5. runs the converter against the bundled XML, with --autoload

Verify with ./check.sh, then in EasyEffects: enable Background Service
+ Autostart (preferences) so the preset survives reboot.
EOF
}

parse_common_flags "$@"
refuse_root

REPO="$RUNBOOK_ROOT/audio/speaker-tuning-to-easyeffects"
REPO_URL="https://github.com/antoinecellerier/speaker-tuning-to-easyeffects.git"
VENV="$REPO/.venv"
XML_DIR="$RUNBOOK_ROOT/audio/xml"
# Exact match for this machine's codec subsystem (ALC287, 17AA:3957).
XML_GLOB="DEV_0287_SUBSYS_17AA3957*.xml"

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

# ------------------------------------------------------- 4. EasyEffects -----
log_step "audio: 4/5 EasyEffects 8"
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
    mgr="$(pkg_manager)"
    case "$mgr" in
        dnf)    pkg_install easyeffects || true ;;
        apt)    pkg_install easyeffects || true ;;
        pacman) pkg_install easyeffects || true ;;
        zypper) pkg_install easyeffects || true ;;
        *)      log_warn "no supported package manager; install EasyEffects 8 yourself (e.g. Flatpak)" ;;
    esac
    if command -v easyeffects >/dev/null 2>&1; then
        log_ok "EasyEffects installed"
    else
        log_warn "EasyEffects not on PATH yet — presets are generated anyway,"
        log_info "install it before they can be used: flatpak install flathub com.github.wwmm.easyeffects"
    fi
fi

# ------------------------------------------------------- 5. converter ------
log_step "audio: 5/5 generate presets from the bundled Windows XML"
mapfile -t xmls < <(compgen -G "$XML_DIR/$XML_GLOB" || true)
if [ "${#xmls[@]}" -eq 0 ]; then
    mapfile -t xmls < <(compgen -G "$XML_DIR"/*.xml || true)
fi
[ "${#xmls[@]}" -gt 0 ] || die "no tuning XML found in $XML_DIR"
if [ "${#xmls[@]}" -gt 1 ]; then
    log_info "multiple XMLs found, using exact subsystem match: ${xmls[0]}"
fi

run "$VENV/bin/python" "$REPO/dolby_to_easyeffects.py" "${xmls[0]}" --autoload

echo
log_ok "presets generated. To keep them after reboot:"
printf '    EasyEffects → preferences → enable Background Service + Autostart\n'
log_info "sound wrong? run the doctor: $VENV/bin/python $REPO/dolby_to_easyeffects.py --doctor"
