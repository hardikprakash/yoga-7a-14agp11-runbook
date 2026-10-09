#!/usr/bin/env bash
# install.sh — copy the Windows-exported ICC profiles into ~/.local/share/icc.
# Copy, never move: the runbook keeps its own pristine copies, the originals
# already in ~/.local/share/icc are left alone (byte-identical = no-op).

set -euo pipefail
# shellcheck source=../lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

usage() {
    cat <<EOF
color-profiles module — import Windows-exported ICC/ICM profiles.

  ./install.sh [--dry-run] [--yes]

Copies color-profiles/icc/* into ~/.local/share/icc (per-user, no sudo).
Assign them afterwards in GNOME Settings → Appearance → Color, or with
colormgr. See color-profiles/README.md.
EOF
}

parse_common_flags "$@"
refuse_root

SRC="$RUNBOOK_ROOT/color-profiles/icc"
DST="${XDG_DATA_HOME:-$HOME/.local/share}/icc"

[ -d "$SRC" ] || die "no profiles directory at $SRC"

log_step "color-profiles: installing to $DST"
run mkdir -p "$DST"

copied=0 updated=0 skipped=0
for f in "$SRC"/*; do
    [ -f "$f" ] || continue
    name="$(basename "$f")"
    target="$DST/$name"
    if [ -f "$target" ] && cmp -s "$f" "$target"; then
        skipped=$((skipped + 1))
        continue
    fi
    if [ -f "$target" ]; then
        updated=$((updated + 1))
    else
        copied=$((copied + 1))
    fi
    run cp -p "$f" "$target"
done

log_ok "profiles: $copied new, $updated updated, $skipped unchanged"
echo
log_ok "installed. Assign them now:"
printf '    GNOME Settings → Appearance → Color (pick the display, choose the profile)\n'
log_info "or headless: colormgr import-profile file://$DST/<name>.icm"
