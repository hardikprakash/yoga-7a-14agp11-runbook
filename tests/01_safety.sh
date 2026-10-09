#!/usr/bin/env bash
# 01_safety.sh — static scan: no script may contain an unguarded risky
# operation. Risky = bootloader/initramfs/cmdline edits, arbitrary rm -rf,
# curl|sh, running as root, or executing the hdr fix's install path.
#
# This is a static guard: even if every other test passed, a future edit
# that sneaks a dangerous command into a setup script fails here.

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
# shellcheck source=lib_test.sh
source tests/lib_test.sh

RUNBOOK_SCRIPTS=(setup.sh lib.sh
    cli/install.sh cli/setup_shell_functions.sh cli/setup_bash_completion.sh cli/check.sh
    audio/install.sh audio/uninstall.sh audio/audio_lib.sh audio/check.sh
    fingerprint/install.sh fingerprint/check.sh
    touchscreen/install.sh touchscreen/uninstall.sh touchscreen/check.sh
    color-profiles/install.sh color-profiles/check.sh
    hdr/check.sh)

echo "== 01 safety: static scan of runbook scripts =="

for s in "${RUNBOOK_SCRIPTS[@]}"; do
    assert_file_exists "$s" "script present: $s"
done

# --- 1. nothing outside hdr/ may *execute* bootloader/initramfs machinery ---
# Matches command invocations only (start of line / after run|sudo), so
# comments and printed instructions that merely mention these are fine.
for s in "${RUNBOOK_SCRIPTS[@]}"; do
    case "$s" in
        hdr/check.sh) continue ;;   # read-only probes, checked below
    esac
    hits="$(grep -nE '(^|[[:space:]])(run[[:space:]]+)?(sudo[[:space:]]+)?(mkinitcpio|grub-mkconfig|dracut|dracut-rebuild|update-grub|limine-update|grub2-mkconfig)([[:space:]]|$)|>>?[[:space:]]*/etc/(default/grub|kernel/cmdline|mkinitcpio)' "$s" 2>/dev/null || true)"
    # Ignore pure comments: strip lines whose first non-space char is '#'.
    hits="$(grep -vE '^[[:space:]]*#' <<<"$hits" || true)"
    if [ -n "$hits" ]; then
        _fail "$s executes bootloader/initramfs machinery: $hits"
    else
        _pass "$s: no bootloader/initramfs execution"
    fi
done

# hdr/check.sh may *read* these paths but never write (no redirect/sed -i).
if grep -nE 'sed -i|>>|mkinitcpio -P|dracut-rebuild' hdr/check.sh >/dev/null 2>&1; then
    _fail "hdr/check.sh writes to system config"
else
    _pass "hdr/check.sh: read-only"
fi

# --- 2. setup.sh must never invoke the hdr fix's install.sh ----------------
if grep -nE 'hdr-edid-fix/(install|uninstall)\.sh' setup.sh | grep -v '^\s*#' | grep -vE 'uninstall\.sh.*reverse|prints' >/dev/null; then
    # Allow mention in printed instructions, forbid execution (i.e. a line
    # where it is not inside a heredoc/echo). Heuristic: execution lines
    # contain 'run ' or start with the path as a command.
    if grep -nE '(^|run |exec )[[:space:]]*[^#]*hdr-edid-fix/install\.sh' setup.sh >/dev/null; then
        _fail "setup.sh executes hdr-edid-fix/install.sh"
    else
        _pass "setup.sh only mentions the hdr installer in text"
    fi
else
    _pass "setup.sh does not reference hdr-edid-fix install path"
fi

# --- 3. no curl|sh, no wget|bash -------------------------------------------
hits="$(grep -rnE 'curl .*\|\s*(ba)?sh|wget .*\|\s*(ba)?sh|curl .*\|\s*sudo' "${RUNBOOK_SCRIPTS[@]}" 2>/dev/null || true)"
if [ -n "$hits" ]; then
    _fail "pipe-to-shell found: $hits"
else
    _pass "no curl|sh patterns"
fi

# --- 4. no unguarded rm -rf on broad paths ---------------------------------
hits="$(grep -rnE 'rm -rf?[[:space:]]+("|)?/\$\{?[A-Z_]*\}?["[:space:]]*$|rm -rf?[[:space:]]+/[[:space:]]' "${RUNBOOK_SCRIPTS[@]}" 2>/dev/null || true)"
if [ -n "$hits" ]; then
    _fail "rm -rf on a root-ish path: $hits"
else
    _pass "no rm -rf on broad paths"
fi
# The only rm -rf allowed is on the venv inside the repo (narrow, known path).
rm_hits="$(grep -rn 'rm -rf' "${RUNBOOK_SCRIPTS[@]}" 2>/dev/null || true)"
while IFS= read -r line; do
    [ -n "$line" ] || continue
    if grep -qE 'VENV|\.venv' <<<"$line"; then
        _pass "narrow rm -rf (venv recreate): ${line%%:*}"
    else
        _fail "unexpected rm -rf: $line"
    fi
done <<<"$rm_hits"

# --- 5. scripts refuse to run as root --------------------------------------
for s in setup.sh cli/install.sh cli/setup_shell_functions.sh \
         cli/setup_bash_completion.sh \
         audio/install.sh audio/uninstall.sh fingerprint/install.sh \
         touchscreen/install.sh touchscreen/uninstall.sh \
         color-profiles/install.sh; do
    # cli installer is user-level-only (writes ~/.bashrc) and would just
    # fail weirdly as root — require an explicit guard or a $HOME write that
    # cannot reach system paths.
    if grep -q 'refuse_root\|EUID\|id -u' "$s"; then
        _pass "$s: has a root guard"
    else
        _fail "$s: no root refusal guard"
    fi
done

# --- 6. every script passes bash -n ----------------------------------------
for s in "${RUNBOOK_SCRIPTS[@]}" tests/*.sh; do
    if bash -n "$s" 2>/tmp/opencode/syntax-err.$$; then
        _pass "syntax: $s"
    else
        _fail "syntax: $s — $(cat /tmp/opencode/syntax-err.$$)"
    fi
    rm -f /tmp/opencode/syntax-err.$$
done

# --- 7. no hard-coded personal/home paths in runbook scripts ---------------
hits="$(grep -rnE '/home/[a-z][a-z0-9_-]*|/Users/' "${RUNBOOK_SCRIPTS[@]}" README.md */README.md 2>/dev/null || true)"
if [ -n "$hits" ]; then
    _fail "hard-coded home paths: $hits"
else
    _pass "no hard-coded home paths"
fi

# --- 8. dry-run must perform zero mutations --------------------------------
sandbox_home
allow_mutations
out="$(./setup.sh all --dry-run 2>&1)" || true
assert_no_mutations "./setup.sh all --dry-run"
assert_contains "$out" "(dry-run)" "dry-run output marks planned actions"
assert_contains "$out" "hdr" "dry-run still explains the hdr manual steps"

finish
