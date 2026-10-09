#!/usr/bin/env bash
# Shared helpers for the runbook scripts. Source this, never execute:
#
#   source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"   # from a module dir
#   source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"      # from the root
#
# Provides: logging, dry-run execution, confirmation prompts, cross-distro
# package installation, and the "ok:/warn:/fail:/info:" line format that
# ./setup.sh status parses out of every module's check.sh.

# Guard against double-sourcing (set -u friendly).
if [ -n "${_RUNBOOK_LIB_SOURCED:-}" ]; then
    return 0 2>/dev/null || true
fi
_RUNBOOK_LIB_SOURCED=1

# Root of the runbook, derived from this file's own location. Everything
# else refers to "$RUNBOOK_ROOT" — never a hard-coded home path.
RUNBOOK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# DRY_RUN=1 -> run() prints instead of executing; confirm() never prompts.
DRY_RUN="${DRY_RUN:-0}"

# ---------------------------------------------------------------- logging ----
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    _c_bold=$'\033[1m'; _c_blue=$'\033[34m'; _c_green=$'\033[32m'
    _c_yellow=$'\033[33m'; _c_red=$'\033[31m'; _c_reset=$'\033[0m'
else
    _c_bold=''; _c_blue=''; _c_green=''; _c_yellow=''; _c_red=''; _c_reset=''
fi

log_info() { printf '%s==%s %s\n' "$_c_blue" "$_c_reset" "$*"; }
log_ok()   { printf '%s  ok%s %s\n' "$_c_green" "$_c_reset" "$*"; }
log_warn() { printf '%s  warn%s %s\n' "$_c_yellow" "$_c_reset" "$*" >&2; }
log_err()  { printf '%s  fail%s %s\n' "$_c_red" "$_c_reset" "$*" >&2; }
log_step() { printf '\n%s-- %s%s\n' "$_c_bold" "$*" "$_c_reset"; }

die() { log_err "$*"; exit 1; }

# ------------------------------------------------------------ check lines ----
# The check.sh contract: every line starts with one of these prefixes,
# exit status is 1 if any fail: line was printed, else 0.
# setup.sh status maps them to the dashboard symbols.
chk_ok()   { printf 'ok: %s\n' "$*"; }
chk_warn() { printf 'warn: %s\n' "$*"; }
chk_fail() { printf 'fail: %s\n' "$*"; }
chk_info() { printf 'info: %s\n' "$*"; }

# ------------------------------------------------------------ dry-run run ----
# run CMD ARGS...  — executes, or prints "[dry-run] CMD ARGS" when DRY_RUN=1.
run() {
    if [ "$DRY_RUN" = 1 ]; then
        printf '  %s(dry-run)%s %s\n' "$_c_blue" "$_c_reset" "$*"
        return 0
    fi
    "$@"
}

# ----------------------------------------------------------- confirmation ----
# confirm "question" — y/N prompt. Auto-yes in dry-run (nothing is touched
# anyway), auto-no when stdin is not a TTY unless RUNBOOK_ASSUME_YES=1.
confirm() {
    local _q="${1:-Proceed?}" _reply
    if [ "$DRY_RUN" = 1 ]; then
        log_info "(dry-run) would ask: $_q"
        return 0
    fi
    if [ "${RUNBOOK_ASSUME_YES:-0}" = 1 ]; then
        log_info "auto-yes: $_q"
        return 0
    fi
    if [ ! -t 0 ]; then
        log_warn "not a terminal, declining: $_q (use RUNBOOK_ASSUME_YES=1 to override)"
        return 1
    fi
    printf '%s [y/N] ' "$_q"
    read -r _reply || return 1
    case "$_reply" in
        y|Y|yes|YES|Yes) return 0 ;;
        *) return 1 ;;
    esac
}

# ------------------------------------------------------------------- root ----
refuse_root() {
    if [ "${EUID:-$(id -u)}" -eq 0 ]; then
        die "do not run this as root — it edits files in \$HOME. sudo is only used where the script asks for it."
    fi
}

# ------------------------------------------------------------ pkg helper -----
pkg_manager() {
    if command -v dnf >/dev/null 2>&1; then echo dnf
    elif command -v apt-get >/dev/null 2>&1; then echo apt
    elif command -v pacman >/dev/null 2>&1; then echo pacman
    elif command -v zypper >/dev/null 2>&1; then echo zypper
    else echo none
    fi
}

pkg_installed() {
    local pkg="$1"
    case "$(pkg_manager)" in
        dnf)     rpm -q "$pkg" >/dev/null 2>&1 ;;
        apt)     dpkg -s "$pkg" >/dev/null 2>&1 ;;
        pacman)  pacman -Qi "$pkg" >/dev/null 2>&1 ;;
        zypper)  rpm -q "$pkg" >/dev/null 2>&1 ;;
        *)       return 1 ;;
    esac
}

# pkg_install PKG... — asks for confirmation once, then installs with the
# native package manager. Returns non-zero if the user declines.
pkg_install() {
    local mgr; mgr="$(pkg_manager)"
    case "$mgr" in
        none) log_warn "no supported package manager found; install manually: $*"; return 1 ;;
        dnf)    confirm "Install with sudo: dnf install $* ?" || { log_warn "skipped: $*"; return 1; } ;;
        apt)    confirm "Install with sudo: apt-get install $* ?" || { log_warn "skipped: $*"; return 1; } ;;
        pacman) confirm "Install with sudo: pacman -S $* ?" || { log_warn "skipped: $*"; return 1; } ;;
        zypper) confirm "Install with sudo: zypper install $* ?" || { log_warn "skipped: $*"; return 1; } ;;
    esac
    case "$mgr" in
        dnf)     run sudo dnf install -y "$@" ;;
        apt)     run sudo apt-get install -y "$@" ;;
        pacman)  run sudo pacman -S --needed --noconfirm "$@" ;;
        zypper)  run sudo zypper --non-interactive install "$@" ;;
    esac
}

# --------------------------------------------------------- misc helpers ------
require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "required command not found: $1${2:+ ($2)}"
}

# Common flag parsing for module scripts: --dry-run, --yes, -h/--help.
# Sets: DRY_RUN, RUNBOOK_ASSUME_YES; calls your usage() for --help.
parse_common_flags() {
    local arg
    for arg in "$@"; do
        case "$arg" in
            --dry-run) DRY_RUN=1 ;;
            --yes|-y)  RUNBOOK_ASSUME_YES=1 ;;
            -h|--help) usage 2>/dev/null || true; exit 0 ;;
            *)         die "unknown flag: $arg (try --help)" ;;
        esac
    done
    export DRY_RUN RUNBOOK_ASSUME_YES
}
