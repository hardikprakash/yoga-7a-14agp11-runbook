#!/usr/bin/env bash
# Install hardware recovery functions into ~/.bashrc.
#
#   ./setup_shell_functions.sh              install/refresh the functions
#   ./setup_shell_functions.sh --dry-run    print what would change
#
# Four self-contained functions, each escalating only when a check fails:
#
#   bt_reset        Bluetooth: rfkill + BlueZ restart + HCI power-cycle.
#                   If the adapter does not come back, reloads btusb.
#   bt_audio_reset  bt_reset + restart PipeWire/WirePlumber.
#   audio_reset     PipeWire/WirePlumber restart only (no Bluetooth).
#   wifi_reset      Wi-Fi: nmcli radio cycle. If the interface does not
#                   come back, reloads rtw89_8922ae via NetworkManager.
#
# Idempotent: the previously installed block is removed before rewriting,
# so re-running never duplicates. The functions are appended between
# marker lines; nothing else in your ~/.bashrc is touched.

set -euo pipefail

DRY_RUN="${DRY_RUN:-0}"
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        -h|--help)
            sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "unknown flag: $arg (try --help)" >&2; exit 1 ;;
    esac
done

if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    echo "do not run as root — this appends to your user's ~/.bashrc" >&2
    exit 1
fi

BASHRC="${BASHRC:-$HOME/.bashrc}"   # overridable for tests
START_MARKER="# === Hardware recovery functions ==="
END_MARKER="# === End hardware recovery functions ==="

if [ ! -f "$BASHRC" ]; then
    echo "note: $BASHRC does not exist yet, it will be created" >&2
    [ "$DRY_RUN" = 1 ] || : > "$BASHRC"
fi

# Remove our previous functions, if they exist (idempotent refresh).
# The markers contain no regex-special characters, so they are safe as-is.
had_block=0
if [ -f "$BASHRC" ] && grep -qF "$START_MARKER" "$BASHRC"; then
    had_block=1
    if [ "$DRY_RUN" = 1 ]; then
        echo "(dry-run) would replace the existing block in $BASHRC"
    else
        sed -i "/^$START_MARKER\$/,/^$END_MARKER\$/d" "$BASHRC"
    fi
fi

BLOCK=$(cat <<'FUNCS'

# === Hardware recovery functions ===
# Installed by yoga-7a-14agp11-runbook/cli/setup_shell_functions.sh.
# Each function escalates only when its post-step check fails.

# --------------------------------------------------------------- helpers ---

# True if a Bluetooth controller is listed and powered on.
_bt_alive() {
    bluetoothctl list 2>/dev/null | grep -q . || return 1
    bluetoothctl show 2>/dev/null | grep -q "Powered: yes"
}

# True if a Wi-Fi interface exists and is not blocked/unavailable.
_wifi_alive() {
    local iface
    for iface in /sys/class/net/*/wireless; do
        [ -e "$iface" ] || continue
        ! rfkill list wifi 2>/dev/null | grep -q "Soft blocked: yes" && return 0
    done
    return 1
}

# True if the user PipeWire stack answers.
_audio_alive() {
    systemctl --user is-active --quiet pipewire &&
    systemctl --user is-active --quiet wireplumber
}

# Restart the user audio stack (PipeWire, PulseAudio bridge, WirePlumber).
_audio_restart() {
    systemctl --user restart pipewire
    systemctl --user restart pipewire-pulse
    systemctl --user restart wireplumber
    sleep 2
}

# ------------------------------------------------------------ Bluetooth ----

# Light Bluetooth reset, escalating to a btusb reload only if the
# adapter does not come back:
#   1. clear rfkill, restart BlueZ, power-cycle the HCI controller
#   2. check: controller listed and powered?
#   3. fallback: reload the btusb kernel module, restart BlueZ
bt_reset() {
    echo "Resetting Bluetooth (light)..."

    sudo rfkill unblock bluetooth
    sudo systemctl restart bluetooth
    sleep 1
    bluetoothctl power off 2>/dev/null || true
    sleep 1
    bluetoothctl power on 2>/dev/null || true
    sleep 1

    if _bt_alive; then
        echo "Bluetooth reset complete."
        return 0
    fi

    echo "Adapter did not come back — escalating: reloading btusb..."

    sudo systemctl stop bluetooth
    if ! sudo modprobe -r btusb 2>/dev/null; then
        echo "btusb is in use and cannot be unloaded; skipping module reload." >&2
    fi
    sudo modprobe btusb
    sleep 1
    sudo systemctl start bluetooth
    sleep 1
    sudo rfkill unblock bluetooth
    bluetoothctl power on 2>/dev/null || true
    sleep 1

    if _bt_alive; then
        echo "Bluetooth nuke complete."
    else
        echo "Bluetooth still dead after btusb reload. Check: dmesg | tail -30" >&2
        return 1
    fi
}

# -------------------------------------------------------- Bluetooth audio ---

# Bluetooth + userspace audio reset:
#   1. bt_reset (which may escalate on its own)
#   2. restart PipeWire / PipeWire-Pulse / WirePlumber
#   3. check: audio stack active again?
bt_audio_reset() {
    echo "Resetting Bluetooth audio..."
    bt_reset || return 1

    echo "Restarting PipeWire/WirePlumber..."
    _audio_restart

    if _audio_alive; then
        echo "Bluetooth audio reset complete."
    else
        echo "Audio stack did not come back. Check: systemctl --user status pipewire" >&2
        return 1
    fi
}

# ------------------------------------------------------------------ audio ---

# Userspace audio reset (no Bluetooth involvement):
#   1. restart PipeWire / PipeWire-Pulse / WirePlumber
#   2. check: stack active again?
audio_reset() {
    echo "Resetting audio stack..."
    _audio_restart

    if _audio_alive; then
        echo "Audio reset complete."
    else
        echo "Audio stack did not come back. Check: systemctl --user status pipewire" >&2
        return 1
    fi
}

# ----------------------------------------------------------------- Wi-Fi ----

# Light Wi-Fi reset, escalating to an RTL8922AE module reload only if
# the interface does not come back:
#   1. toggle the Wi-Fi radio via NetworkManager
#   2. check: interface present, not rfkill-blocked?
#   3. fallback: stop NM, reload rtw89_8922ae, clear rfkill, start NM
wifi_reset() {
    echo "Resetting Wi-Fi (light)..."

    nmcli radio wifi off
    sleep 1
    nmcli radio wifi on
    sleep 1

    if _wifi_alive; then
        echo "Wi-Fi reset complete."
        return 0
    fi

    echo "Interface did not come back — escalating: reloading rtw89_8922ae..."

    sudo nmcli radio wifi off
    sudo systemctl stop NetworkManager
    sleep 1
    if ! sudo modprobe -r rtw89_8922ae 2>/dev/null; then
        echo "rtw89_8922ae is in use and cannot be unloaded; skipping module reload." >&2
    fi
    sudo modprobe rtw89_8922ae
    sleep 1
    sudo rfkill unblock wifi
    sudo systemctl start NetworkManager
    sleep 2
    nmcli radio wifi on
    sleep 1

    if _wifi_alive; then
        echo "Wi-Fi nuke complete."
    else
        echo "Wi-Fi still dead after driver reload. Check: dmesg | tail -30" >&2
        return 1
    fi
}

# === End hardware recovery functions ===
FUNCS
)

if [ "$DRY_RUN" = 1 ]; then
    echo "(dry-run) would append the function block to $BASHRC ($(wc -l <<<"$BLOCK") lines)"
    if [ "$had_block" = 1 ]; then
        echo "(dry-run) existing block would be replaced, not duplicated"
    fi
    exit 0
fi

printf '%s\n' "$BLOCK" >> "$BASHRC"

echo
if [ "$had_block" = 1 ]; then
    echo "Hardware recovery functions refreshed (previous block replaced)."
else
    echo "Hardware recovery functions installed."
fi
echo
echo "Available commands (run 'source $BASHRC' or open a new shell):"
echo "  bt_reset        Bluetooth, escalating to btusb reload"
echo "  bt_audio_reset  Bluetooth + audio stack"
echo "  audio_reset     audio stack only"
echo "  wifi_reset      Wi-Fi, escalating to rtw89_8922ae reload"
