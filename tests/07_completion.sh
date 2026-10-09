#!/usr/bin/env bash
# 07_completion.sh — bash tab completion for ./setup.sh:
#   * installer: idempotent marker block, dry-run mutates nothing
#   * the completion function completes commands, per-module flags and
#     flag values (both `--flag value` and `--flag=value` forms)
#   * context-awareness: audio-only flags only after audio/all
#   * survives a fresh interactive shell (bash -ic)

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
# shellcheck source=lib_test.sh
source tests/lib_test.sh

echo "== 07 completion =="

START_MARKER="# === setup.sh tab completion ==="
END_MARKER="# === End setup.sh tab completion ==="

# Helper: run the completion function as bash's completion machinery would.
# comp "<line>" — line = what the user typed so far (trailing space = new word).
comp() {
    local line="$1"
    read -ra COMP_WORDS <<<"$line"
    COMP_CWORD=$(( ${#COMP_WORDS[@]} - 1 ))
    case "$line" in
        *" ") COMP_WORDS+=(""); COMP_CWORD=$((COMP_CWORD + 1)) ;;
    esac
    COMPREPLY=()
    _setup_runbook
}

# the completion function must exist (source the canonical file)
# shellcheck source=../completions/setup.bash
source completions/setup.bash
_pass "completion function loads"

# =============================================== 1. command completions =====
comp "./setup.sh "
assert_contains "${COMPREPLY[*]}" "status" "completes 'status'"
assert_contains "${COMPREPLY[*]}" "audio" "completes 'audio'"
assert_contains "${COMPREPLY[*]}" "color-profiles" "completes 'color-profiles'"
assert_contains "${COMPREPLY[*]}" "--dry-run" "completes common --dry-run"

comp "./setup.sh a"
mapfile -t only_a < <(printf '%s\n' "${COMPREPLY[@]}")
assert_eq "${#only_a[@]}" 2 "'a' narrows to 2 matches (all, audio)"
assert_contains "${only_a[*]}" "all" "'a' matches 'all'"
assert_contains "${only_a[*]}" "audio" "'a' matches 'audio'"

# ================================================ 2. flag context rules =====
comp "./setup.sh audio "
assert_contains "${COMPREPLY[*]}" "--backend" "after 'audio': --backend offered"
assert_contains "${COMPREPLY[*]}" "--variant" "after 'audio': --variant offered"
assert_contains "${COMPREPLY[*]}" "--force" "after 'audio': --force offered"

comp "./setup.sh cli "
assert_not_contains "${COMPREPLY[*]}" "--backend" "after 'cli': no --backend"
assert_not_contains "${COMPREPLY[*]}" "--variant" "after 'cli': no --variant"
assert_not_contains "${COMPREPLY[*]}" "--force" "after 'cli': no --force"
assert_contains "${COMPREPLY[*]}" "--dry-run" "after 'cli': common flags still offered"

comp "./setup.sh all "
assert_contains "${COMPREPLY[*]}" "--backend" "after 'all': --backend offered (forwarded to audio)"

comp "./setup.sh hdr "
assert_not_contains "${COMPREPLY[*]}" "--backend" "after 'hdr': no --backend"

# ============================================== 3. flag-value completions ====
comp "./setup.sh audio --backend "
mapfile -t be_vals < <(printf '%s\n' "${COMPREPLY[@]}")
assert_eq "${#be_vals[@]}" 4 "--backend offers 4 values"
assert_contains "${COMPREPLY[*]}" "easyeffects" "--backend offers easyeffects"
assert_contains "${COMPREPLY[*]}" "pipewire" "--backend offers pipewire"
assert_contains "${COMPREPLY[*]}" "ee" "--backend offers alias ee"
assert_contains "${COMPREPLY[*]}" "pw" "--backend offers alias pw"

comp "./setup.sh audio --backend p"
assert_eq "${#COMPREPLY[@]}" 2 "'--backend p' narrows to pipewire+pw"
assert_contains "${COMPREPLY[*]}" "pipewire" "'p' matches pipewire"

comp "./setup.sh audio --variant "
mapfile -t var_vals < <(printf '%s\n' "${COMPREPLY[@]}")
assert_eq "${#var_vals[@]}" 4 "--variant offers 4 values (incl. all)"

comp "./setup.sh audio --variant w"
assert_eq "${#COMPREPLY[@]}" 1 "'--variant w' narrows to warm"
assert_eq "${COMPREPLY[0]}" "warm" "'w' completes exactly 'warm'"

# equals form
comp "./setup.sh audio --backend="
assert_eq "${#COMPREPLY[@]}" 4 "--backend= offers 4 values"
assert_eq "${COMPREPLY[0]}" "--backend=easyeffects" "--backend= keeps the flag prefix"

comp "./setup.sh audio --variant=d"
assert_eq "${#COMPREPLY[@]}" 1 "'--variant=d' narrows"
assert_eq "${COMPREPLY[0]}" "--variant=detailed" "--variant=d completes --variant=detailed"

# values must not leak into a context that rejects the flag: after 'cli',
# --variant gets no voicing values — it falls back to plain flag completion
comp "./setup.sh cli --backend "
assert_eq "${#COMPREPLY[@]}" 5 "after 'cli --backend': falls back to the 5 common flags"
assert_not_contains "${COMPREPLY[*]}" "pipewire" "no backend values after 'cli'"
comp "./setup.sh cli --variant "
assert_not_contains "${COMPREPLY[*]}" "balanced" "no voicing values after 'cli'"
assert_not_contains "${COMPREPLY[*]}" "warm" "no voicing values after 'cli' (warm)"

# flags after a completed value still complete
comp "./setup.sh audio --backend pipewire "
assert_contains "${COMPREPLY[*]}" "--force" "flags still complete after a value"

# =========================================== 4. installer idempotency =======
sandbox_home
./cli/setup_bash_completion.sh >/dev/null 2>&1; rc=$?
assert_rc "$rc" 0 "installer succeeds"
assert_file_exists "$BASHRC" "bashrc created/updated"
assert_contains "$(cat "$BASHRC")" "$START_MARKER" "start marker present"
assert_contains "$(cat "$BASHRC")" "$END_MARKER" "end marker present"
assert_contains "$(cat "$BASHRC")" "_setup_runbook()" "completion function installed"

./cli/setup_bash_completion.sh >/dev/null 2>&1
n_blocks=$(grep -c "^$START_MARKER\$" "$BASHRC")
assert_eq "$n_blocks" "1" "re-run keeps exactly one block (idempotent)"

# dry-run mutates nothing
cp "$BASHRC" "$TEST_TMP/bashrc.before"
./cli/setup_bash_completion.sh --dry-run >/dev/null 2>&1
if cmp -s "$BASHRC" "$TEST_TMP/bashrc.before"; then
    _pass "dry-run leaves bashrc byte-identical"
else
    _fail "dry-run modified bashrc"
fi

# the root guard is asserted statically in 01_safety.sh (grep for the
# EUID check); it cannot be exercised at runtime without being root,
# which the suite refuses to be.

# cli/install.sh drives both sub-installers
sandbox_home
./cli/install.sh >/dev/null 2>&1; rc=$?
assert_rc "$rc" 0 "cli/install.sh succeeds"
assert_contains "$(cat "$BASHRC")" "# === Hardware recovery functions ===" "cli install adds functions"
assert_contains "$(cat "$BASHRC")" "$START_MARKER" "cli install adds completion"

# ================================= 5. installed block works in a fresh shell =
out="$(bash -ic '
source ~/.bashrc 2>/dev/null
read -ra COMP_WORDS <<< "./setup.sh audio --variant "
COMP_CWORD=3
COMPREPLY=()
_setup_runbook
echo "${COMPREPLY[*]}"
' 2>/dev/null | tail -1)"
assert_contains "$out" "balanced" "installed block completes in a fresh bash -ic"
assert_contains "$out" "warm" "installed block offers warm"

# and the block parses under bash -n (installed into a real bashrc)
sandbox_home
./cli/setup_bash_completion.sh >/dev/null 2>&1
if bash -n "$BASHRC" 2>/dev/null; then
    _pass "installed bashrc parses (bash -n)"
else
    _fail "installed bashrc has a syntax error"
fi

finish
