#!/usr/bin/env bash
# 06_backends.sh — audio backend choice (easyeffects vs pipewire):
#   * flag parsing: both syntaxes, aliases, missing/bad values, no hangs
#   * setup.sh routes module flags correctly (audio gets them, others don't)
#   * check.sh detects: none / one / both staged (both = conflict, exit 1)
#   * uninstall.sh removes exactly what it claims, per backend, idempotently
#   * switching prompts to remove the other backend; dry-run never deletes

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
# shellcheck source=lib_test.sh
source tests/lib_test.sh

echo "== 06 backends =="

# ---------------------------------------------------------------- helpers ---
# Stage fake files in the sandbox HOME/XDG dirs.
stage_ee() {
    local d="${XDG_DATA_HOME}/easyeffects"
    mkdir -p "$d/output" "$d/irs" "$d/autoload/output"
    echo '{"_generator":"test","output":{"blocklist":[],"plugins_order":[]}}' \
        > "$d/output/Dolby-Balanced.json"
    echo '{"_generator":"test","output":{"blocklist":[],"plugins_order":[]}}' \
        > "$d/output/Nothing.json"
    printf 'IRS' > "$d/irs/Dolby-Balanced-test.irs"
    printf '{"device":"x","preset-name":"Dolby-Balanced"}' \
        > "$d/autoload/output/test-sink:Speaker.json"
}
stage_pw() {
    local d="${XDG_CONFIG_HOME}/pipewire/pipewire.conf.d"
    mkdir -p "$d"
    printf 'context.objects=[]\n' > "$d/Dolby_Balanced.conf"
    printf 'IRS' > "$d/Dolby_Balanced.irs"
}

# =============================================== 1. flag parsing (install) ===
sandbox_home
allow_mutations

# equals syntax (was an infinite loop bug — timeout guards the regression)
out="$(timeout 10 ./audio/install.sh --backend=pipewire --dry-run 2>&1)"; rc=$?
assert_rc "$rc" 0 "install --backend=pipewire (equals) completes, no hang"
assert_contains "$out" "backend: pipewire" "equals syntax sets the backend"

# two-token syntax
out="$(timeout 10 ./audio/install.sh --backend pipewire --dry-run 2>&1)"; rc=$?
assert_rc "$rc" 0 "install --backend pipewire (two tokens) completes"
assert_contains "$out" "backend: pipewire" "two-token syntax sets the backend"

# aliases
out="$(timeout 10 ./audio/install.sh --backend ee --dry-run 2>&1)"
assert_contains "$out" "backend: easyeffects" "alias 'ee' resolves"
out="$(timeout 10 ./audio/install.sh --backend pw --dry-run 2>&1)"
assert_contains "$out" "backend: pipewire" "alias 'pw' resolves"

# bad value names the offender
out="$(timeout 10 ./audio/install.sh --backend nope 2>&1)"; rc=$?
assert_rc "$rc" 1 "bad backend value fails"
assert_contains "$out" "unknown backend 'nope'" "bad value is named in the error"

# missing value
out="$(timeout 10 ./audio/install.sh --backend 2>&1)"; rc=$?
assert_rc "$rc" 1 "missing backend value fails"
assert_contains "$out" "needs a value" "missing value is explained"

# variant parsing: good value accepted, bad rejected
out="$(timeout 10 ./audio/install.sh --backend pipewire --variant warm --dry-run 2>&1)"; rc=$?
assert_rc "$rc" 0 "valid --variant accepted"
assert_contains "$out" "variant: warm" "variant shown in backend line"
out="$(timeout 10 ./audio/install.sh --variant nope --dry-run 2>&1)"; rc=$?
assert_rc "$rc" 1 "bad --variant fails"
assert_contains "$out" "unknown variant 'nope'" "bad variant named"

# unknown flags still rejected
out="$(timeout 10 ./audio/install.sh --frobnicate 2>&1)"; rc=$?
assert_rc "$rc" 1 "unknown flag fails"
assert_contains "$out" "unknown flag: --frobnicate" "unknown flag named"

# ============================================ 2. setup.sh flag routing ======
sandbox_home
allow_mutations

out="$(timeout 10 ./setup.sh audio --backend=pw --dry-run 2>&1)"; rc=$?
assert_rc "$rc" 0 "setup.sh audio --backend=pw routes through"
assert_contains "$out" "backend: pipewire" "setup.sh forwards backend to audio"

# module flags must not leak to other modules
out="$(timeout 10 ./setup.sh cli --backend pw 2>&1)"; rc=$?
assert_rc "$rc" 1 "backend flag on cli is rejected"
assert_contains "$out" "belong to the audio module" "rejection explains ownership"

# setup.sh rejects unknown flags itself
out="$(timeout 10 ./setup.sh audio --frobnicate 2>&1)"; rc=$?
assert_rc "$rc" 1 "setup.sh rejects unknown flag"
assert_contains "$out" "unknown flag: --frobnicate" "unknown flag named by setup.sh"

# `all` accepts backend flags (forwarded to audio only) — dry-run proves it
out="$(timeout 30 ./setup.sh all --backend pw --dry-run 2>&1)"; rc=$?
assert_rc "$rc" 0 "all --backend pw --dry-run completes"
assert_contains "$out" "backend: pipewire" "all forwards backend to audio"
assert_not_contains "$out" "unknown flag" "other modules don't choke on --backend"
assert_no_mutations "./setup.sh all --backend pw --dry-run"

# --help for the module (not setup.sh's own help)
out="$(timeout 10 ./setup.sh audio --help 2>&1)"
assert_contains "$out" "--backend easyeffects|pipewire" "audio --help shows backend docs"

# ======================================== 3. check.sh route detection =======
# none staged → fail with guidance
sandbox_home
out="$(bash ./audio/check.sh 2>&1)"; rc=$?
assert_rc "$rc" 1 "no route staged → check fails"
assert_contains "$out" "no route installed" "check reports nothing installed"
assert_contains "$out" "--backend pipewire" "check mentions both backends"

# only easyeffects staged
stage_ee
out="$(bash ./audio/check.sh 2>&1)"; rc=$?
assert_rc "$rc" 0 "ee-only staged → check passes"
assert_contains "$out" "easyeffects route" "ee route reported"
assert_contains "$out" "presets + speaker autoload" "autoload detected"
assert_not_contains "$out" "both routes" "no false conflict"

# pipewire only staged
rm -rf "${XDG_DATA_HOME}/easyeffects"
stage_pw
out="$(bash ./audio/check.sh 2>&1)"; rc=$?
assert_rc "$rc" 0 "pw-only staged → check passes"
assert_contains "$out" "pipewire route" "pw route reported"
assert_contains "$out" "NOT loaded" "inactive pw chain flagged (no pw-dump match)"

# BOTH staged → conflict, exit 1
stage_ee
out="$(bash ./audio/check.sh 2>&1)"; rc=$?
assert_rc "$rc" 1 "both staged → conflict, check fails"
assert_contains "$out" "both routes staged" "conflict named"
assert_contains "$out" "--uninstall --backend easyeffects" "conflict offers removal commands"

# ================================================== 4. uninstall per backend =
# NOTE: confirm() declines when stdin is not a TTY (deliberate — no silent
# deletion from pipes/scripts), so positive cases pass --yes.

# ee-only uninstall removes ee files, leaves pw files
stage_pw
out="$(./audio/uninstall.sh --backend easyeffects --yes 2>&1)"; rc=$?
assert_rc "$rc" 0 "ee uninstall succeeds"
assert_file_absent "${XDG_DATA_HOME}/easyeffects/output/Dolby-Balanced.json" "ee preset removed"
assert_file_absent "${XDG_DATA_HOME}/easyeffects/irs/Dolby-Balanced-test.irs" "ee impulse removed"
assert_file_absent "${XDG_DATA_HOME}/easyeffects/autoload/output/test-sink:Speaker.json" "ee autoload removed"
assert_file_absent "${XDG_DATA_HOME}/easyeffects/output/Nothing.json" "Nothing.json removed"
assert_file_exists "${XDG_CONFIG_HOME}/pipewire/pipewire.conf.d/Dolby_Balanced.conf" "pw files untouched by ee uninstall"

# idempotent: second run says nothing staged, still rc 0
out="$(./audio/uninstall.sh --backend easyeffects --yes 2>&1)"; rc=$?
assert_rc "$rc" 0 "second ee uninstall is a no-op success"
assert_contains "$out" "nothing staged" "idempotent: reports nothing staged"

# pw uninstall removes conf+irs and restarts user pipewire (stubbed+logged)
allow_mutations
out="$(./audio/uninstall.sh --backend pipewire --yes 2>&1)"; rc=$?
assert_rc "$rc" 0 "pw uninstall succeeds"
assert_file_absent "${XDG_CONFIG_HOME}/pipewire/pipewire.conf.d/Dolby_Balanced.conf" "pw conf removed"
assert_file_absent "${XDG_CONFIG_HOME}/pipewire/pipewire.conf.d/Dolby_Balanced.irs" "pw impulse removed"
assert_mutations_logged "pw uninstall restarts the user PipeWire chain" "systemctl --user restart pipewire"

# decline → nothing removed (interactive path, TTY check bypassed by piping
# into a here-string still counts as non-TTY → decline; assert both angles)
stage_ee
out="$(./audio/uninstall.sh --backend easyeffects </dev/null 2>&1)"; rc=$?
assert_rc "$rc" 1 "non-interactive without --yes declines"
assert_file_exists "${XDG_DATA_HOME}/easyeffects/output/Dolby-Balanced.json" "non-interactive decline removes nothing"
assert_contains "$out" "not a terminal" "decline reason is explained"

# --yes auto-confirms (how install.sh calls it when switching)
out="$(./audio/uninstall.sh --backend easyeffects --yes 2>&1)"; rc=$?
assert_rc "$rc" 0 "--yes uninstall succeeds"
assert_file_absent "${XDG_DATA_HOME}/easyeffects/output/Dolby-Balanced.json" "--yes removed the preset"

# ================================================ 5. dry-run deletes nothing =
stage_ee; stage_pw
allow_mutations
out="$(./audio/uninstall.sh --dry-run 2>&1)"; rc=$?
assert_rc "$rc" 0 "dry-run uninstall completes"
assert_contains "$out" "nothing was actually deleted" "dry-run says so"
assert_contains "$out" "would remove" "dry-run uses conditional wording"
assert_file_exists "${XDG_DATA_HOME}/easyeffects/output/Dolby-Balanced.json" "dry-run kept ee preset"
assert_file_exists "${XDG_CONFIG_HOME}/pipewire/pipewire.conf.d/Dolby_Balanced.conf" "dry-run kept pw conf"
assert_no_mutations "dry-run uninstall performs no mutations (incl. no pipewire restart)"

# ================================= 6. switching prompts to remove the other =
# ee staged → pipewire install offers to switch (dry-run: prompt only)
allow_mutations
out="$(timeout 30 ./setup.sh audio --backend pipewire --dry-run 2>&1)"; rc=$?
assert_rc "$rc" 0 "switch ee→pw dry-run completes"
assert_contains "$out" "switching backend (easyeffects → pipewire)" "switch detected"
assert_contains "$out" "would ask" "switch asks for confirmation (dry-run form)"
assert_contains "$out" "would remove the easyeffects route" "dry-run wording for the switch"
assert_file_exists "${XDG_DATA_HOME}/easyeffects/output/Dolby-Balanced.json" "dry-run switch removed nothing"
assert_no_mutations "dry-run switch performs no mutations"

# ======================================================== 7. setup.sh --uninstall
out="$(timeout 10 ./setup.sh audio --uninstall --dry-run 2>&1)"; rc=$?
assert_rc "$rc" 0 "setup.sh audio --uninstall routes to uninstall.sh"
assert_contains "$out" "would remove" "uninstall dry-run lists removals"
assert_contains "$out" "dry-run: nothing was actually deleted" "uninstall dry-run confirms nothing deleted"

out="$(timeout 10 ./setup.sh cli --uninstall 2>&1)"; rc=$?
assert_rc "$rc" 1 "cli has no uninstall.sh → clear error"
assert_contains "$out" "has no uninstall.sh" "missing uninstall named"

out="$(timeout 10 ./setup.sh hdr --uninstall 2>&1)"; rc=$?
assert_rc "$rc" 1 "hdr --uninstall stays manual"
assert_contains "$out" "manual" "hdr uninstall points at the manual path"

out="$(timeout 10 ./setup.sh all --uninstall 2>&1)"; rc=$?
assert_rc "$rc" 1 "all --uninstall rejected"
assert_contains "$out" "per module" "rejection explains per-module uninstall"

finish
