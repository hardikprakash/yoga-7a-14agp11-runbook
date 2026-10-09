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
# Common flags captured by main() and forwarded to every module in `all`.
SETUP_COMMON=()

usage() {
    cat <<EOF
${_c_bold}yoga-7a-14agp11 runbook setup${_c_reset}

Usage:
  ./setup.sh status               show what is installed and what is missing
  ./setup.sh all [--dry-run]      run every automatable module, in order
                                  (audio's --backend/--variant work here too
                                  and are forwarded to audio only)
  ./setup.sh <module> [...]       run one module:
                                  ${MODULES[*]}
  ./setup.sh <module> --uninstall run that module's uninstall.sh
                                  (available: audio, touchscreen)
  ./setup.sh help                 this text

Common flags (every command):
  --dry-run    print every action instead of performing it
  --yes, -y    answer yes to confirmation prompts (incl. sudo)
  -h, --help   show help (for a module: that module's usage)

audio module flags:
  --backend easyeffects|pipewire   how to apply the Dolby tuning
                                   (aliases: ee, pw; default: easyeffects)
  --variant balanced|detailed|warm  pipewire backend only: which voicing
  --force                          pipewire backend only: overwrite an
                                   existing Dolby_*.conf instead of failing

Notes:
  * sudo is only ever used after an explicit confirmation (see --yes).
  * ./setup.sh hdr never edits the bootloader itself; it prints the steps.
  * module flags are validated by their own module, so a typo in
    --backend surfaces with the audio module's message.
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
# $@ = audio-only flags (--backend/--variant); forwarded to audio alone,
# because cli/fingerprint/... do not understand them. Common flags
# (--dry-run/--yes) come from SETUP_COMMON and go to every module.
cmd_all() {
    local -a audio_flags=("$@")
    local m failed=() rc

    log_step "Running all automatable modules: ${INSTALL_ORDER[*]}"
    for m in "${INSTALL_ORDER[@]}"; do
        local install="$ROOT/$m/install.sh"
        if [ ! -f "$install" ]; then
            log_warn "$m: no install.sh, skipping"
            continue
        fi
        log_step "module: $m"
        local -a mod_args=("${SETUP_COMMON[@]+"${SETUP_COMMON[@]}"}")
        if [ "$m" = audio ] && [ "${#audio_flags[@]}" -gt 0 ]; then
            mod_args+=("${audio_flags[@]}")
        fi
        rc=0
        bash "$install" ${mod_args[@]+"${mod_args[@]}"} || rc=$?
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

    # Split argv: setup-level flags, audio module flags (forwarded only to
    # audio), the --uninstall dispatch switch, and -h/--help. Anything else
    # is rejected here with a pointer to --help.
    local -a common=() audio_flags=()
    local uninstall=0 want_help=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --dry-run|--yes|-y) common+=("$1") ;;
            --uninstall)        uninstall=1 ;;
            -h|--help)          want_help=1 ;;
            --force)            audio_flags+=("$1") ;;
            --backend|--variant)
                [ $# -ge 2 ] || die "$1 needs a value (see --help)"
                audio_flags+=("$1" "$2"); shift ;;
            --backend=*|--variant=*)
                audio_flags+=("$1") ;;
            *) die "unknown flag: $1 (try --help)" ;;
        esac
        shift
    done

    # Audio-only flags may never go to another module.
    if [ "${#audio_flags[@]}" -gt 0 ] && [ "$cmd" != audio ] && [ "$cmd" != all ]; then
        die "'${audio_flags[0]}' belongs to the audio module (try: ./setup.sh audio ...)"
    fi

    case "$cmd" in
        -h|--help|help) usage ;;
        status)
            if [ "$want_help" = 1 ]; then usage; return; fi
            [ "$uninstall" = 1 ] && die "status takes no --uninstall"
            [ "${#audio_flags[@]}" -eq 0 ] || die "status takes no module flags"
            parse_common_flags ${common[@]+"${common[@]}"}
            cmd_status ;;
        all)
            if [ "$want_help" = 1 ]; then usage; return; fi
            [ "$uninstall" = 1 ] && die "'all' has no --uninstall — run it per module: ./setup.sh <module> --uninstall"
            parse_common_flags ${common[@]+"${common[@]}"}
            refuse_root
            SETUP_COMMON=("${common[@]+"${common[@]}"}")
            cmd_all ${audio_flags[@]+"${audio_flags[@]}"} ;;
        *)
            if is_module "$cmd"; then
                if [ "$cmd" = hdr ]; then
                    # hdr has no install.sh of its own: it only ever prints
                    # status + manual instructions (bootloader risk).
                    [ "$uninstall" = 1 ] &&
                        die "hdr's uninstall is manual: cd hdr/hdr-edid-fix && sudo ./uninstall.sh (bootloader edit)"
                    parse_common_flags ${common[@]+"${common[@]}"}
                    refuse_root
                    cmd_hdr
                    return
                fi
                [ "$want_help" = 1 ] && { bash "$ROOT/$cmd/install.sh" -h; return; }
                local script="$ROOT/$cmd/install.sh"
                if [ "$uninstall" = 1 ]; then
                    script="$ROOT/$cmd/uninstall.sh"
                    [ -f "$script" ] || die "module '$cmd' has no uninstall.sh"
                fi
                [ -f "$script" ] || die "module '$cmd' has no install.sh"
                parse_common_flags ${common[@]+"${common[@]}"}
                refuse_root
                local -a fwd=("${common[@]+"${common[@]}"}")
                if [ "$cmd" = audio ] && [ "${#audio_flags[@]}" -gt 0 ]; then
                    fwd+=("${audio_flags[@]}")
                fi
                bash "$script" ${fwd[@]+"${fwd[@]}"}
            else
                die "unknown command: $cmd (try --help)"
            fi
            ;;
    esac
}

main "$@"
