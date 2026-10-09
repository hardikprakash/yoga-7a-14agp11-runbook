#!/usr/bin/env bash
# Install bash tab completion for ./setup.sh into ~/.bashrc.
#
#   ./setup_bash_completion.sh              install/refresh the completion
#   ./setup_bash_completion.sh --dry-run    print what would change
#
# Sources completions/setup.bash (kept in the runbook, so updates flow
# through re-running this) inside a marker block. Idempotent: the previous
# block is replaced, never duplicated. Completion only helps in new shells —
# run `source ~/.bashrc` or open a terminal afterwards.

set -euo pipefail

DRY_RUN="${DRY_RUN:-0}"
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        -h|--help)
            sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "unknown flag: $arg (try --help)" >&2; exit 1 ;;
    esac
done

if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    echo "do not run as root — this appends to your user's ~/.bashrc" >&2
    exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPLETION="$ROOT/completions/setup.bash"
[ -f "$COMPLETION" ] || { echo "completion file missing: $COMPLETION" >&2; exit 1; }

BASHRC="${BASHRC:-$HOME/.bashrc}"   # overridable for tests
START_MARKER="# === setup.sh tab completion ==="
END_MARKER="# === End setup.sh tab completion ==="

if [ ! -f "$BASHRC" ]; then
    echo "note: $BASHRC does not exist yet, it will be created" >&2
    [ "$DRY_RUN" = 1 ] || : > "$BASHRC"
fi

had_block=0
if [ -f "$BASHRC" ] && grep -qF "$START_MARKER" "$BASHRC"; then
    had_block=1
    if [ "$DRY_RUN" = 1 ]; then
        echo "(dry-run) would replace the existing completion block in $BASHRC"
    else
        sed -i "/^$START_MARKER\$/,/^$END_MARKER\$/d" "$BASHRC"
    fi
fi

if [ "$DRY_RUN" = 1 ]; then
    echo "(dry-run) would append to $BASHRC:"
    echo "  $START_MARKER"
    sed 's/^/  /' "$COMPLETION"
    echo "  $END_MARKER"
    exit 0
fi

{
    printf '\n%s\n' "$START_MARKER"
    cat "$COMPLETION"
    printf '%s\n' "$END_MARKER"
} >> "$BASHRC"

echo
if [ "$had_block" = 1 ]; then
    echo "setup.sh tab completion refreshed (previous block replaced)."
else
    echo "setup.sh tab completion installed."
fi
echo "Active in new shells — or run: source $BASHRC"
echo "Try: ./setup.sh <Tab>   ./setup.sh audio --backend <Tab>"
