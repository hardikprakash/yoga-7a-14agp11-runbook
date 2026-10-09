#!/usr/bin/env bash
# check.sh — read-only status of the color-profiles module.
# Compares the runbook's bundled profiles against ~/.local/share/icc.

set -euo pipefail
# shellcheck source=../lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

SRC="$RUNBOOK_ROOT/color-profiles/icc"
DST="${XDG_DATA_HOME:-$HOME/.local/share}/icc"

if [ ! -d "$SRC" ]; then
    chk_fail "no bundled profiles in $SRC"
    exit 1
fi

total=0 present=0 differing=() missing=()
for f in "$SRC"/*; do
    [ -f "$f" ] || continue
    total=$((total + 1))
    name="$(basename "$f")"
    if [ ! -f "$DST/$name" ]; then
        missing+=("$name")
    elif ! cmp -s "$f" "$DST/$name"; then
        differing+=("$name")
    else
        present=$((present + 1))
    fi
done

if [ "$total" -eq 0 ]; then
    chk_fail "bundled profile folder is empty"
    exit 1
fi

if [ "${#missing[@]}" -eq 0 ] && [ "${#differing[@]}" -eq 0 ]; then
    chk_ok "$present/$total profiles installed in $DST"
    chk_info "assign in Settings → Appearance → Color; colormgr get-devices shows assignment"
elif [ "$present" -gt 0 ]; then
    chk_warn "$present/$total installed; missing: ${missing[*]:-none}; differing: ${differing[*]:-none}"
    chk_info "run ./setup.sh color-profiles"
else
    chk_fail "none of the $total bundled profiles are in $DST"
    chk_info "run ./setup.sh color-profiles"
    exit 1
fi
