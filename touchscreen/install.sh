#!/usr/bin/env bash
# install.sh — WACF2200 touchscreen unbind/rebind workaround (needs sudo).
# Extracted verbatim from touchscreen/README.md; read that first.
#
# Writes /usr/local/bin/wacf2200-rebind.sh and enables
# wacf2200-rebind.service. Reboot afterwards.

set -euo pipefail
# shellcheck source=../lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

usage() {
    cat <<EOF
touchscreen module — boot-time I2C unbind/rebind for the Wacom touch panel.

  ./install.sh [--dry-run] [--yes]

Installs (with sudo, after confirmation):
  /usr/local/bin/wacf2200-rebind.sh
  /etc/systemd/system/wacf2200-rebind.service   (enabled)

Uninstall: ./uninstall.sh   Verify: ./check.sh   Details: README.md
EOF
}

parse_common_flags "$@"
refuse_root

log_step "touchscreen: installing rebind workaround (sudo, after confirmation)"

if ! confirm "Install wacf2200-rebind.sh + systemd service (writes to /usr/local and /etc)?"; then
    die "declined"
fi

# Device names are machine-specific: AMDI0010:02 = the touchscreen's I2C
# controller, AMDI0030:00 = the pinctrl-amd GPIO controller we wait for.
# See README.md "Adapting to another machine" before changing them.
run sudo tee /usr/local/bin/wacf2200-rebind.sh >/dev/null <<'EOF'
#!/bin/bash
# Rebind AMDI0010:02 (WACF2200 touchscreen's I2C controller) once
# pinctrl-amd (amd_gpio) has bound. Works around a probe-ordering race
# on Lenovo Yoga 7 14AGP11 between i2c-designware and pinctrl-amd.
for i in $(seq 1 50); do
    if [ -e /sys/bus/platform/devices/AMDI0030:00/driver ]; then
        logger -t wacf2200-rebind "amd_gpio bound after ${i} checks, rebinding"
        break
    fi
    sleep 0.1
done

if [ -e /sys/bus/platform/devices/AMDI0010:02/driver ]; then
    echo -n "AMDI0010:02" > /sys/bus/platform/drivers/i2c_designware/unbind
fi
sleep 0.5
echo -n "AMDI0010:02" > /sys/bus/platform/drivers/i2c_designware/bind
logger -t wacf2200-rebind "Rebind complete"
EOF
run sudo chmod +x /usr/local/bin/wacf2200-rebind.sh

run sudo tee /etc/systemd/system/wacf2200-rebind.service >/dev/null <<'EOF'
[Unit]
Description=Rebind WACF2200 touchscreen I2C controller after pinctrl-amd binds
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/wacf2200-rebind.sh

[Install]
WantedBy=multi-user.target
EOF
run sudo systemctl daemon-reload
run sudo systemctl enable wacf2200-rebind.service

echo
log_ok "installed and enabled."
log_info "reboot, then verify: ./check.sh  (and journalctl -b -t wacf2200-rebind)"
