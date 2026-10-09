# Yoga 7 14AGP11: Wacom touchscreen workaround (unbind/rebind at boot)

Workaround for a non-working WACF2200 Wacom touchscreen and stylus on the
Lenovo Yoga 7 2-in-1 14AGP11 (83TD). A boot-time systemd service unbinds and
rebinds the touchscreen's I2C controller once the system has finished booting.

**Tested on:** Fedora 44, kernel `7.2.5-200.fc44.x86_64`. Touch and stylus both
work after a cold reboot with no manual steps.

> **Scripted install:** the steps below are also available as
> [`install.sh`](install.sh) / [`uninstall.sh`](uninstall.sh) (sudo, with a
> confirmation prompt) and [`check.sh`](check.sh) for status — the manual
> blocks remain the source of truth.

A user on a Yoga 7 16AGP11 (Ubuntu 24.04) reported that the manual
unbind/rebind also works there. The device name may differ on other models, so
see "Adapting to another machine" below.

## Symptoms

At boot, `dmesg` shows repeated errors on the touchscreen's I2C controller, and
no touchscreen or stylus input devices appear:

```
i2c_designware AMDI0010:02: i2c_dw_handle_tx_abort: lost arbitration
```

A working boot shows `input: WACF2200:00 ... Touchscreen` and `... Stylus`
lines instead.

## Background

- `i2c_designware` probes `AMDI0010:02` before `pinctrl-amd` (`AMDI0030:00`)
  has finished initialising. The first I2C transactions to the touchscreen then
  fail with lost arbitration.
- Unbinding and rebinding `AMDI0010:02` after boot gets past the race, because
  by then the GPIO controller is ready.
- An upstream fix (`0a4bb2abc3e5`, "i2c: designware: defer probe if child
  GpioInt controllers are not bound") was merged and then reverted by Linus
  (`d5b95e612cde`) for 7.2. It caused touchpad init failures on some ThinkPads
  (T14s Gen 4 AMD) and probe-deferral problems on other hardware.
- The ThinkPad regression is thought to be an EC/APU I2C bus-master handoff
  timing issue (Mario Limonciello's hypothesis). That was never confirmed.
- A cleaner fix direction was suggested by Hans de Goede: have `i2c-hid-core`
  request its IRQ before its connectivity check and defer if that fails. As far
  as I know that has not been implemented.
- Remove this workaround if a kernel update fixes the race upstream.

## Install

Run as a user with sudo access.

**1. The rebind script**

```bash
sudo tee /usr/local/bin/wacf2200-rebind.sh > /dev/null << 'EOF'
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
sudo chmod +x /usr/local/bin/wacf2200-rebind.sh
```

**2. The systemd service**

```bash
sudo tee /etc/systemd/system/wacf2200-rebind.service > /dev/null << 'EOF'
[Unit]
Description=Rebind WACF2200 touchscreen I2C controller after pinctrl-amd binds
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/wacf2200-rebind.sh

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable wacf2200-rebind.service
```

**3. Reboot and verify**

```bash
sudo reboot
```

After boot:

```bash
journalctl -b -t wacf2200-rebind --no-pager
systemctl status wacf2200-rebind.service --no-pager
sudo dmesg | grep -E "arbitration|WACF|Wacom"
```

Expected result:

- The journal shows "Rebind complete".
- `dmesg` may still show the early `lost arbitration` lines, because the race
  still happens on the first probe. They should be followed by `WACF2200` and
  `Wacom HID` input devices registering after the rebind.
- Touch and stylus work.

## Manual one-off test (no install needed)

```bash
echo -n "AMDI0010:02" | sudo tee /sys/bus/platform/drivers/i2c_designware/unbind
sleep 2
echo -n "AMDI0010:02" | sudo tee /sys/bus/platform/drivers/i2c_designware/bind
```

## Adapting to another machine

The script hard-codes two device names:

- `AMDI0010:02` is the I2C controller the touchscreen sits on. To find yours,
  look at which controller reports the arbitration errors:

  ```bash
  sudo dmesg | grep "lost arbitration"
  ```

  The controller name in those lines (for example `AMDI0010:02`) is the one to
  use. On this machine the touchscreen is the ACPI device `WACF2200:00`, a child
  of that controller.
- `AMDI0030:00` is the `pinctrl-amd` GPIO controller the script waits for.
  Confirm it exists with:

  ```bash
  ls /sys/bus/platform/devices/ | grep AMDI0030
  ```

If either name differs, edit the script before installing.

## What did not work

A udev rule triggered on the `bind` event of `AMDI0030:00` worked when I forced
the event with `udevadm trigger --action=bind`, but never fired at a real boot.
My best guess is that `pinctrl-amd` binds very early, before the rule is loaded
from the real root filesystem, so the event is already gone. A systemd service
that runs late in boot does not have this problem.

## Not tested

- Suspend/resume behaviour. I did not check whether the touchscreen survives
  resume or needs another rebind.
- Other kernel versions or distros beyond those listed at the top.

## Uninstall

```bash
sudo systemctl disable --now wacf2200-rebind.service
sudo rm /etc/systemd/system/wacf2200-rebind.service /usr/local/bin/wacf2200-rebind.sh
sudo systemctl daemon-reload
```

## References

- Wacom GitHub issue tracking this laptop (my updates and the unbind/rebind tip
  are in the comments).
- Kernel bugzilla: https://bugzilla.kernel.org/show_bug.cgi?id=221494
