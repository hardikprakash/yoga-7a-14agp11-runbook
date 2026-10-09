#!/usr/bin/env bash
# Runbook orchestrator for the Lenovo Yoga 7 2-in-1 14AGP11.
#
#   ./setup.sh status              read-only dashboard of every module
#   ./setup.sh all [--dry-run]     run every safe module in order
#   ./setup.sh <module> [...]      run one module (cli|fingerprint|audio|
#                                  color-profiles|touchscreen|hdr)
#
# Flags: --dry-run (print actions, touch nothing), --yes (auto-confirm
# prompts, including sudo), -h/--help.
#
# "all" never executes anything that edits the bootloader, initramfs or
# the kernel command line — the hdr module only prints instructions.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$ROOT/lib.sh"

# User-level first, sudo last so as few prompts as possible happen early.
MODULES=(cli fingerprint audio color-profiles touchscreen hdr)
INSTALL_ORDER=(cli fingerprint audio color-profiles touchscreen)

usage() {
    cat <<EOF
${_c_bold}yoga-7a-14agp11 runbook setup${_c_reset}

Usage:
  ./setup.sh status               show what is installed and what is missing
  ./setup.sh all [--dry-run]      run every automatable module, in order
  ./setup.sh <module> [...]       run one module:
                                  ${MODULES[*]}
  ./setup.sh help                 this text

Flags:
  --dry-run    print every action instead of performing it
  --yes, -y    answer yes to confirmation prompts (incl. sudo)
  -h, --help   show help for a module

Notes:
  * sudo is only ever used after an explicit confirmation (see --yes).
  * ./setup.sh hdr never edits the bootloader itself; it prints the steps.
EOF
}

# ----------------------------------------------------------------- status ----
# Runs every module's check.sh (read-only probing is fine), renders
# ✅ / ⚠️ / ❌ per module, and exits 1 if anything failed.
cmd_status() {
    local m rc out n_ok n_warn n_fail n_info symbol line
    local total_fail=0 total_warn=0

    log_step "Runbook status"
    for m in "${MODULES[@]}"; do
        local check="$ROOT/$m/check.sh"
        if [ ! -f "$check" ]; then
            printf '❓ %-16s no check.sh\n' "$m"
            continue
        fi
        rc=0
        out="$(bash "$check" 2>&1)" || rc=$?

        n_ok=$(grep -c '^ok: ' <<<"$out" || true)
        n_warn=$(grep -c '^warn: ' <<<"$out" || true)
        n_fail=$(grep -c '^fail: ' <<<"$out" || true)
        n_info=$(grep -c '^info: ' <<<"$out" || true)

        if [ "$n_fail" -gt 0 ] || [ "$rc" -ne 0 ]; then
            symbol="❌"; total_fail=$((total_fail + 1))
        elif [ "$n_warn" -gt 0 ]; then
            symbol="⚠️ "; total_warn=$((total_warn + 1))
        else
            symbol="✅"
        fi

        # Headline must match the symbol rendered above: prefer the first
        # fail, else warn, else ok line; the rest are printed as details.
        local headline_pattern headline
        if [ "$n_fail" -gt 0 ] || [ "$rc" -ne 0 ]; then
            headline_pattern='^fail: '
        elif [ "$n_warn" -gt 0 ]; then
            headline_pattern='^warn: '
        else
            headline_pattern='^ok: '
        fi
        headline="$(grep -m1 "$headline_pattern" <<<"$out" || true)"
        [ -n "$headline" ] || headline="$(grep -m1 -E '^(ok|warn|fail): ' <<<"$out" || true)"

        printf '%s %-16s %s\n' "$symbol" "$m" "${headline#*: }"
        while IFS= read -r line; do
            [ -n "$line" ] || continue
            [ "$line" = "$headline" ] && continue
            printf '     %s\n' "$line"
        done <<<"$out"
    done

    echo
    if [ "$total_fail" -gt 0 ]; then
        log_warn "$total_fail module(s) need attention, $total_warn with warnings — see above"
        return 1
    elif [ "$total_warn" -gt 0 ]; then
        log_ok "all modules installed, $total_warn with warnings"
    else
        log_ok "everything is installed"
    fi
}

# ------------------------------------------------------------------- all ----
cmd_all() {
    local m failed=() rc

    log_step "Running all automatable modules: ${INSTALL_ORDER[*]}"
    for m in "${INSTALL_ORDER[@]}"; do
        local install="$ROOT/$m/install.sh"
        if [ ! -f "$install" ]; then
            log_warn "$m: no install.sh, skipping"
            continue
        fi
        log_step "module: $m"
        rc=0
        bash "$install" "$@" || rc=$?
        if [ "$rc" -ne 0 ]; then
            failed+=("$m")
            log_warn "$m: did not complete (exit $rc)"
        fi
    done

    print_hdr_instructions

    echo
    if [ "${#failed[@]}" -gt 0 ]; then
        log_warn "finished with failures in: ${failed[*]}"
        return 1
    fi
    log_ok "finished."
    printf '%s\n' "Reboot needed for: touchscreen (apply the I2C rebind at boot)."
}

# ------------------------------------------------------------------- hdr ----
# Deliberately never runs hdr-edid-fix/install.sh: it rewrites the kernel
# command line and the initramfs. Print the steps instead.
print_hdr_instructions() {
    log_step "HDR: manual steps (never automated)"
    cat <<'EOF'
  The HDR fix edits the kernel command line and the initramfs — one bad
  edit and the panel stays dark at boot, so it is not run automatically.
  Follow hdr/README.md:

    1. ./setup.sh hdr            (this: shows what applies to this machine)
    2. cd hdr/hdr-edid-fix
       ./edid/patch-edid.py --check     # should report an HDR metadata block
       sudo ./install.sh                # patched EDID + cmdline + initramfs
    3. reboot
    4. ./check.sh                # verify the chain end to end
    5. optional, washed-out-HDR: mutter patch, see hdr/README.md

  Undo any time with: sudo ./uninstall.sh   (in hdr/hdr-edid-fix/)
EOF
}

cmd_hdr() {
    # Cloning is safe — only hdr-edid-fix's install.sh (bootloader/initramfs)
    # is kept manual. Auto-clone here so status/instructions always work.
    local fix="$RUNBOOK_ROOT/hdr/hdr-edid-fix"
    if [ ! -d "$fix/.git" ]; then
        require_cmd git "to clone hdr-edid-fix"
        log_step "hdr: cloning Boogie61/hdr-edid-fix"
        run git clone https://github.com/Boogie61/hdr-edid-fix.git "$fix"
    fi

    # Show the machine-specific status first, then the instructions.
    if [ -f "$ROOT/hdr/check.sh" ]; then
        bash "$ROOT/hdr/check.sh" || true
        echo
    fi
    print_hdr_instructions
}

# ------------------------------------------------------------------ main ----
is_module() {
    local m
    for m in "${MODULES[@]}"; do
        [ "$1" = "$m" ] && return 0
    done
    return 1
}

main() {
    local cmd="${1:-help}"
    [ $# -gt 0 ] && shift || true

    case "$cmd" in
        -h|--help|help) usage ;;
        status)         parse_common_flags "$@"; cmd_status ;;
        all)            parse_common_flags "$@"; refuse_root; cmd_all "$@" ;;
        *)
            if is_module "$cmd"; then
                parse_common_flags "$@"
                refuse_root
                if [ "$cmd" = hdr ]; then
                    cmd_hdr
                else
                    local install="$ROOT/$cmd/install.sh"
                    [ -f "$install" ] || die "module '$cmd' has no install.sh"
                    bash "$install" "$@"
                fi
            else
                die "unknown command: $cmd (try --help)"
            fi
            ;;
    esac
}

main "$@"
