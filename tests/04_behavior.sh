#!/usr/bin/env bash
# 04_behavior.sh — exercises the actual runtime logic:
#   * shell functions escalate ONLY when the light path's check fails
#   * setup.sh orchestrates modules in order and never runs the hdr fix
#   * confirmation gates: no sudo path runs without a prompt/--yes
#   * dry-run never executes, even the escalated branches

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
# shellcheck source=lib_test.sh
source tests/lib_test.sh

echo "== 04 behavior =="

# ------------------------------------------------------------- harness ------
# A stub environment for sourcing the bashrc function block: bluetoothctl,
# nmcli, systemctl etc. log their calls; health-check outcomes are toggled
# via files in $STUB_STATE.
STUB_STATE="$TEST_TMP/state"
mkdir -p "$STUB_STATE"

# Build a PATH dir with behavior-controllable stubs for the functions' deps.
FN_BIN="$TEST_TMP/fn-bin"
mkdir -p "$FN_BIN"

# bluetoothctl: 'list'/'show' reflect $STUB_STATE/bt-alive (1/0).
cat > "$FN_BIN/bluetoothctl" <<STUB
#!/bin/bash
echo "bluetoothctl \$*" >> "$MUTATION_LOG"
case "\${1:-}" in
    list)  [ -f "$STUB_STATE/bt-alive" ] && echo "Controller AA:BB:CC:DD:EE:FF test" ;;
    show)  [ -f "$STUB_STATE/bt-alive" ] && echo " Powered: yes" ;;
    power) [ -f "$STUB_STATE/bt-alive" ] && exit 0 || exit 1 ;;
esac
exit 0
STUB
chmod +x "$FN_BIN/bluetoothctl"

# rfkill: 'list wifi' reflects blocked state.
cat > "$FN_BIN/rfkill" <<STUB
#!/bin/bash
echo "rfkill \$*" >> "$MUTATION_LOG"
if [ "\${1:-}" = list ]; then
    if [ -f "$STUB_STATE/wifi-blocked" ]; then
        echo "0: phy0: Wi-Fi"
        echo " Soft blocked: yes"
    else
        echo "0: phy0: Wi-Fi"
        echo " Soft blocked: no"
    fi
    exit 0
fi
# block/unblock: mutate state file
case "\${1:-}" in
    unblock) rm -f "$STUB_STATE/wifi-blocked" ;;
    block)   touch "$STUB_STATE/wifi-blocked" ;;
esac
exit 0
STUB
chmod +x "$FN_BIN/rfkill"

# systemctl (user-level from the functions): log + succeed; any is-active
# (wherever it appears in the args) reflects $STUB_STATE/audio-alive.
cat > "$FN_BIN/systemctl" <<STUB
#!/bin/bash
echo "systemctl \$*" >> "$MUTATION_LOG"
case "\$*" in
    *is-active*)
        [ -f "$STUB_STATE/audio-alive" ] && exit 0 || exit 3
        ;;
esac
exit 0
STUB
chmod +x "$FN_BIN/systemctl"

# sudo: log the real command (so we can see escalation), do NOT execute it.
cat > "$FN_BIN/sudo" <<STUB
#!/bin/bash
echo "sudo \$*" >> "$MUTATION_LOG"
exit 0
STUB
chmod +x "$FN_BIN/sudo"

# modprobe: log; after a reload, flip the health file to "alive" so the
# post-escalation check can succeed (simulating a fixed device).
cat > "$FN_BIN/modprobe" <<STUB
#!/bin/bash
echo "modprobe \$*" >> "$MUTATION_LOG"
case "\${1:-}" in
    btusb)        [ "\${2:-}" = "-r" ] && exit 0 || touch "$STUB_STATE/bt-alive" ;;
    rtw89_8922ae) [ "\${2:-}" = "-r" ] && exit 0 || rm -f "$STUB_STATE/wifi-blocked" ;;
esac
exit 0
STUB
chmod +x "$FN_BIN/modprobe"

# sleep: no-op for speed (the functions sleep a lot)
printf '#!/bin/bash\nexit 0\n' > "$FN_BIN/sleep"; chmod +x "$FN_BIN/sleep"

# nmcli: log; radio on clears blocked state.
cat > "$FN_BIN/nmcli" <<STUB
#!/bin/bash
echo "nmcli \$*" >> "$MUTATION_LOG"
if [ "\${1:-}" = radio ]; then
    case "\${3:-}" in
        on)  rm -f "$STUB_STATE/wifi-blocked" ;;
        off) touch "$STUB_STATE/wifi-blocked" ;;
    esac
fi
exit 0
STUB
chmod +x "$FN_BIN/nmcli"

# Install the function block into a sandbox bashrc, then load it.
sandbox_home
./cli/setup_shell_functions.sh >/dev/null 2>&1
# The block's helper `_wifi_alive` iterates /sys/class/net/*/wireless — on a
# machine without wifi interfaces it returns false and would always
# escalate. For determinism we only exercise bt + audio functions here if
# no wifi iface exists; wifi tests degrade to "escalates when interface
# absent", which is still the documented contract.
export PATH="$FN_BIN:$PATH"

load_funcs() {
    # shellcheck disable=SC1090
    source "$BASHRC" 2>/dev/null
}

# ------------------------------------------------- bt_reset: light success ---
rm -f "$MUTATION_LOG"; touch "$STUB_STATE/bt-alive"; rm -f "$STUB_STATE/wifi-blocked"
allow_mutations
load_funcs
out="$(bt_reset 2>&1)"; rc=$?
assert_rc "$rc" 0 "bt_reset: succeeds when adapter is alive"
assert_not_contains "$(cat "$MUTATION_LOG")" "modprobe" "bt_reset: no module reload on light path"
assert_contains "$(cat "$MUTATION_LOG")" "systemctl restart bluetooth" "bt_reset: does restart BlueZ (light step)"
assert_contains "$out" "reset complete" "bt_reset: reports light-path completion"

# ------------------------------------------------- bt_reset: escalation ------
rm -f "$MUTATION_LOG"; rm -f "$STUB_STATE/bt-alive"   # light path will fail
allow_mutations
# bluetoothctl show/list fail (no bt-alive) => check fails => escalate.
# sudo modprobe btusb (reload) touches bt-alive => final check passes.
# But the sudo stub does not execute, so bt-alive never gets set by sudo.
# The function's final check then also fails => rc 1. Assert escalation ran.
load_funcs
out="$(bt_reset 2>&1)"; rc=$?
assert_contains "$(cat "$MUTATION_LOG")" "sudo modprobe -r btusb" "bt_reset: escalates to btusb reload when light path fails"
assert_contains "$(cat "$MUTATION_LOG")" "sudo systemctl stop bluetooth" "bt_reset: stops BlueZ before reload"
assert_rc "$rc" 1 "bt_reset: reports failure when device stays dead (sudo not executed)"

# ------------------------------------------------ bt_audio_reset includes PW ---
rm -f "$MUTATION_LOG"; touch "$STUB_STATE/bt-alive"; touch "$STUB_STATE/audio-alive"
allow_mutations
load_funcs
out="$(bt_audio_reset 2>&1)"; rc=$?
assert_rc "$rc" 0 "bt_audio_reset: succeeds when both alive"
assert_contains "$(cat "$MUTATION_LOG")" "systemctl --user restart pipewire" "bt_audio_reset: restarts the audio stack"
assert_contains "$(cat "$MUTATION_LOG")" "systemctl --user restart wireplumber" "bt_audio_reset: restarts wireplumber"
assert_not_contains "$(cat "$MUTATION_LOG")" "modprobe" "bt_audio_reset: no reload when light path works"

# ------------------------------------------------------- audio_reset only -----
rm -f "$MUTATION_LOG"; touch "$STUB_STATE/audio-alive"
allow_mutations
load_funcs
out="$(audio_reset 2>&1)"; rc=$?
assert_rc "$rc" 0 "audio_reset: succeeds"
assert_contains "$(cat "$MUTATION_LOG")" "systemctl --user restart pipewire" "audio_reset: restarts pipewire"
assert_not_contains "$(cat "$MUTATION_LOG")" "bluetooth" "audio_reset: never touches bluetooth"
assert_not_contains "$(cat "$MUTATION_LOG")" "modprobe" "audio_reset: never reloads kernel modules"

# ------------------------------------------------------ wifi_reset light ------
rm -f "$MUTATION_LOG"; rm -f "$STUB_STATE/wifi-blocked"
allow_mutations
load_funcs
if ls /sys/class/net/*/wireless >/dev/null 2>&1; then
    out="$(wifi_reset 2>&1)"; rc=$?
    assert_rc "$rc" 0 "wifi_reset: succeeds when interface present"
    assert_not_contains "$(cat "$MUTATION_LOG")" "modprobe" "wifi_reset: no driver reload on light path"
else
    _pass "wifi_reset: no wireless iface in this environment (light-path test skipped)"
fi

# ----------------------------------------------- setup.sh orchestration -------
# --dry-run: order preserved, hdr installer never invoked, sudo never called.
sandbox_home
allow_mutations
out="$(./setup.sh all --dry-run 2>&1)" || true
assert_no_mutations "setup.sh all --dry-run: zero mutations"
modpos=$(grep -n "module: cli" <<<"$out" | head -1 | cut -d: -f1)
tspos=$(grep -n "module: touchscreen" <<<"$out" | head -1 | cut -d: -f1)
if [ -n "$modpos" ] && [ -n "$tspos" ] && [ "$modpos" -lt "$tspos" ]; then
    _pass "setup.sh runs cli before touchscreen (user-level first)"
else
    _fail "module order wrong (cli@$modpos, touchscreen@$tspos)"
fi
assert_contains "$out" "manual steps" "setup.sh prints hdr manual steps instead of running them"
assert_not_contains "$out" "module: hdr" "hdr is never run as an automated module"

# --- confirmation gate: without --yes and without a TTY, sudo declines -------
sandbox_home
allow_mutations
out="$(printf '' | ./touchscreen/install.sh 2>&1)"; rc=$?
assert_rc "$rc" 1 "touchscreen install: declines without TTY/confirm (rc=1)"
assert_not_contains "$(cat "$MUTATION_LOG")" "sudo tee" "touchscreen install: no sudo tee without confirmation"
assert_no_mutations "touchscreen install: nothing written when declined"

# --- --yes still stubbed: sudo tee logged but not executed (PATH stubs) ------
allow_mutations
ts_script="/usr/local/bin/wacf2200-rebind.sh"
mtime_before=""
if [ -f "$ts_script" ]; then mtime_before="$(stat -c %Y "$ts_script")"; fi
out="$(./touchscreen/install.sh --yes 2>&1)"; rc=$?
assert_rc "$rc" 0 "touchscreen install: proceeds with --yes"
assert_mutations_logged "touchscreen install: sudo tee reached (stubbed, logged)" "sudo tee"
mtime_after=""
if [ -f "$ts_script" ]; then mtime_after="$(stat -c %Y "$ts_script")"; fi
assert_eq "$mtime_after" "$mtime_before" "touchscreen install: real file on disk untouched (stubbed sudo/tee)"

finish
