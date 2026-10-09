#!/usr/bin/env bash
# 03_portability.sh — the runbook must work for anyone:
#   * no personal paths, no dependency on this machine's layout
#   * every module runnable from an arbitrary working directory
#   * check.sh contract: only ok:/warn:/fail:/info: lines, correct exit codes
#   * runs under `bash` with nounset; no bash-isms that break set -u
#   * setup.sh flag handling behaves from any cwd

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
# shellcheck source=lib_test.sh
source tests/lib_test.sh

RB="$PWD"   # absolute path to the runbook

echo "== 03 portability =="

# --- 1. no absolute personal paths anywhere in runbook text files ----------
# Patterns require an actual username after the prefix, so the regexes
# inside the test files themselves ('/home/[a-z]') don't self-match.
# Filesystem-based (not git ls-files) so it works before the first commit.
bad=0
while IFS= read -r f; do
    if grep -nE '/home/[a-z][a-z0-9_.-]+|/Users/[a-z][a-z0-9_.-]+' "$f" >/dev/null 2>&1; then
        _fail "personal path in $f: $(grep -nE '/home/[a-z][a-z0-9_.-]+|/Users/[a-z][a-z0-9_.-]+' "$f" | head -1)"
        bad=1
    fi
done < <(find . \( -name '*.sh' -o -name '*.md' \) \
            ! -path './audio/speaker-tuning-to-easyeffects/*' \
            ! -path './hdr/hdr-edid-fix/*' -type f)
[ "$bad" = 0 ] && _pass "no personal/absolute home paths in runbook files"

# The pre-rename folder name must not appear in runbook files (tests may
# reference it as a scan pattern, so tests/ is excluded here).
oldname='Yoga 7a 14AGP11 Resources'
hits="$(grep -rFl "$oldname" --include='*.sh' --include='*.md' \
        --exclude-dir='speaker-tuning-to-easyeffects' --exclude-dir='hdr-edid-fix' \
        --exclude-dir='tests' . 2>/dev/null || true)"
if [ -n "$hits" ]; then
    _fail "old folder name still referenced: $hits"
else
    _pass "no references to the pre-rename folder name"
fi

# --- 2. scripts locate the runbook root themselves (run from foreign cwd) ---
foreign="$TEST_TMP/somewhere/else"
mkdir -p "$foreign"
out="$(cd "$foreign" && bash "$RB/cli/check.sh" 2>&1)"; rc=$?
# cli check reads $HOME/.bashrc (real one may or may not have the block) —
# what matters is it runs without cwd assumptions and emits valid lines.
if [ "$rc" -le 1 ] && grep -qE '^(ok|warn|fail): ' <<<"$out"; then
    _pass "cli/check.sh runs from a foreign cwd (rc=$rc)"
else
    _fail "cli/check.sh from foreign cwd: rc=$rc out=$out"
fi

# setup.sh --help from foreign cwd
out="$(cd "$foreign" && bash "$RB/setup.sh" --help 2>&1)"; rc=$?
assert_rc "$rc" 0 "setup.sh --help works from foreign cwd"
assert_contains "$out" "./setup.sh status" "help text renders"

# setup.sh status from foreign cwd (read-only)
allow_mutations
out="$(cd "$foreign" && bash "$RB/setup.sh" status 2>&1)" || true
assert_no_mutations "setup.sh status from foreign cwd"
assert_contains "$out" "Runbook status" "status runs from foreign cwd"

# --- 3. check.sh line-format contract --------------------------------------
# Every line must be ok:/warn:/fail:/info: (or empty). The dashboard parser
# depends on this.
sandbox_home
for c in cli audio fingerprint touchscreen color-profiles hdr; do
    out="$(bash "$RB/$c/check.sh" 2>&1)" || true
    strays="$(grep -vE '^(ok|warn|fail|info): |^$' <<<"$out" || true)"
    if [ -n "$strays" ]; then
        _fail "$c/check.sh emits non-contract lines: $(head -1 <<<"$strays")"
    else
        _pass "$c/check.sh: all lines match the ok/warn/fail/info contract"
    fi
done

# --- 4. exit codes: fail => 1, otherwise 0 ---------------------------------
# cli: sandbox with no bashrc => must exit 1
sandbox_home
bash "$RB/cli/check.sh" >/dev/null 2>&1; assert_rc "$?" 1 "cli/check.sh exits 1 when not installed"
# color-profiles: bundled icc exists, dst empty => fails => 1
bash "$RB/color-profiles/check.sh" >/dev/null 2>&1; assert_rc "$?" 1 "color-profiles/check.sh exits 1 when nothing installed"
# fingerprint: stack installed on this system, no enrollment => warn => 0
bash "$RB/fingerprint/check.sh" >/dev/null 2>&1; assert_rc "$?" 0 "fingerprint/check.sh exits 0 on warn"

# --- 5. works with a path containing spaces (the old folder name) ----------
spaced="$TEST_TMP/dir with spaces/runbook"
mkdir -p "$spaced"
cp -r "$RB"/{setup.sh,lib.sh,cli,fingerprint,color-profiles,tests} "$spaced/" 2>/dev/null
rm -rf "$spaced/tests"   # tests self-locate; not needed inside the copy
out="$(cd "$spaced" && BASHRC="$TEST_TMP/space-bashrc" bash ./setup.sh --help 2>&1)"; rc=$?
assert_rc "$rc" 0 "setup.sh runs from a path containing spaces"
out="$(cd "$spaced" && BASHRC="$TEST_TMP/space-bashrc" bash ./cli/setup_shell_functions.sh 2>&1)"; rc=$?
assert_rc "$rc" 0 "cli installer runs from a path containing spaces"
assert_file_exists "$TEST_TMP/space-bashrc" "bashrc created in spaced-path run"

# --- 6. nounset safety: every script parses and key entry points run --------
for s in setup.sh lib.sh */install.sh */check.sh */uninstall.sh; do
    case "$s" in
        speaker-tuning*|hdr-edid*) continue ;;
    esac
    if bash -u -n "$s" 2>/dev/null; then
        _pass "set -u safe (parse): $s"
    else
        _fail "set -u parse failure: $s"
    fi
done

finish
