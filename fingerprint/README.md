# fingerprint — Goodix sensor via libfprint

Fedora Workstation does not pull in `libfprint` on a minimal install, so
the Goodix MOC sensor goes unused. This module installs the stack and
tells you how to enroll (enrollment itself is interactive — a script
cannot press your finger for you).

## Install

```bash
./setup.sh fingerprint      # dnf install fprintd libfprint (asks before sudo)
```

## Enroll (interactive, once)

```bash
fprintd-enroll $USER        # lift and place the same finger ~5 times
fprintd-list $USER          # should now report fingers enrolled
```

Then verify anywhere:

```bash
./fingerprint/check.sh      # or ./setup.sh status
```

Lock the session and unlock with a finger for the real-world test.

## Notes

- The daemon is `fprintd`; the driver library is `libfprint`. PAM
  integration (`fprintd`) is what lets GDM/sudo accept a fingerprint.
- Sensor absent? `dmesg | grep -i -E 'goodix|fingerprint|spi'`.
