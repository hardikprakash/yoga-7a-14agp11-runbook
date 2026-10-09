#!/usr/bin/env bash
# 02_idempotency.sh — running any installer twice must be a no-op the
# second time (no duplicate state, no drift), and must preserve unrelated
# pre-existing user content.

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
# shellcheck source=lib_test.sh
source tests/lib_test.sh

echo "== 02 idempotency =="

# --- cli: bashrc block ------------------------------------------------------
sandbox_home
echo "# user's own line, must survive" > "$BASHRC"

out1="$(./cli/setup_shell_functions.sh 2>&1)"; rc1=$?
assert_rc "$rc1" 0 "cli installer: first run succeeds"
assert_contains "$out1" "installed" "cli: first run reports install"
blocks1=$(grep -cF '# === Hardware recovery functions ===' "$BASHRC")
assert_eq "$blocks1" "1" "cli: exactly one block after first run"
assert_contains "$(cat "$BASHRC")" "# user's own line, must survive" "cli: pre-existing content preserved"

out2="$(./cli/setup_shell_functions.sh 2>&1)"; rc2=$?
assert_rc "$rc2" 0 "cli: second run succeeds"
assert_contains "$out2" "refreshed" "cli: second run reports refresh (not new install)"
blocks2=$(grep -cF '# === Hardware recovery functions ===' "$BASHRC")
assert_eq "$blocks2" "1" "cli: still exactly one block after re-run"
assert_contains "$(cat "$BASHRC")" "# user's own line, must survive" "cli: user content survives re-run"

# third run + function definition count stability
./cli/setup_shell_functions.sh >/dev/null 2>&1
def_count=$(grep -cE '^(bt_reset|bt_audio_reset|audio_reset|wifi_reset)\(\)' "$BASHRC")
assert_eq "$def_count" "4" "cli: 4 function definitions after 3 runs"
assert_eq "$(grep -cF '# === Hardware recovery functions ===' "$BASHRC")" "1" "cli: still one block after 3 runs"

# dry-run must not mutate at all
cp "$BASHRC" "$TEST_TMP/bashrc.before"
./cli/setup_shell_functions.sh --dry-run >/dev/null 2>&1
if cmp -s "$BASHRC" "$TEST_TMP/bashrc.before"; then
    _pass "cli: dry-run leaves .bashrc byte-identical"
else
    _fail "cli: dry-run modified .bashrc"
fi

# --- color-profiles: install twice -----------------------------------------
sandbox_home
allow_mutations
./color-profiles/install.sh --yes >/dev/null 2>&1; rc=$?
assert_rc "$rc" 0 "color-profiles: first run succeeds"
n1=$(ls "$HOME/.local/share/icc" | wc -l)
./color-profiles/install.sh --yes >/dev/null 2>&1; rc=$?
assert_rc "$rc" 0 "color-profiles: second run succeeds"
n2=$(ls "$HOME/.local/share/icc" | wc -l)
assert_eq "$n2" "$n1" "color-profiles: file count unchanged on re-run"
assert_eq "$n1" "9" "color-profiles: all 9 bundled profiles copied"
# byte-identical with sources
same=0
for f in color-profiles/icc/*; do
    cmp -s "$f" "$HOME/.local/share/icc/$(basename "$f")" && same=$((same + 1))
done
assert_eq "$same" "9" "color-profiles: copies are byte-identical to sources"
# no system-wide writes (no /usr/share/color/icc churn)
assert_no_mutations "color-profiles: stays user-level"

# --- audio: venv reuse decision is stable (regression: quote-format bug) ----
# Python 3.14's activate writes VIRTUAL_ENV unquoted; an over-strict grep
# used to force a venv recreation on every run.
sandbox_home
allow_mutations
out1="$(./setup.sh audio --dry-run 2>&1)" || true
out2="$(./setup.sh audio --dry-run 2>&1)" || true
if [ -x audio/speaker-tuning-to-easyeffects/.venv/bin/python ]; then
    assert_not_contains "$out1" "recreating" "audio: existing venv judged reusable (no stale-path recreation)"
    assert_contains "$out2" "venv reusable" "audio: second dry-run still reuses the venv"
    assert_no_mutations "./setup.sh audio --dry-run"
else
    _pass "audio: no venv present in this checkout (recreation path, skipped)"
fi

# --- status is read-only ----------------------------------------------------
sandbox_home
allow_mutations
status_out="$(./setup.sh status 2>&1)" || true
assert_no_mutations "./setup.sh status"
assert_contains "$status_out" "cli" "status lists the cli module"
assert_contains "$status_out" "hdr" "status lists the hdr module"

finish
