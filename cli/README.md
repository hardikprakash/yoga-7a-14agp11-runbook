# cli — hardware recovery shell functions

Installs four functions into `~/.bashrc`, each of which **escalates only if
a post-step check fails** (light first, kernel-module reload only as a
fallback):

| Function | Light steps | Escalates to | Fixes |
|---|---|---|---|
| `bt_reset` | rfkill unblock → restart BlueZ → power-cycle the controller | reload `btusb` | BlueZ wedged, adapter vanished, pairing broken |
| `bt_audio_reset` | `bt_reset` + restart PipeWire/Pulse/WirePlumber | (inherits) | BT connects but A2DP gives no audio |
| `audio_reset` | restart PipeWire/Pulse/WirePlumber | — | no speaker sound, missing default sink, xrun storms (no BT involved) |
| `wifi_reset` | `nmcli radio wifi off/on` | stop NM → reload `rtw89_8922ae` → clear rfkill | RTL8922AE firmware wedge, interface gone, scans that never return |

The escalation checks: `_bt_alive` (controller listed + powered),
`_wifi_alive` (interface present + not rfkill-blocked),
`_audio_alive` (user pipewire + wireplumber units active).

## Install

```bash
./setup.sh cli              # or: cd cli && ./setup_shell_functions.sh
source ~/.bashrc            # new shells get them automatically
```

Re-running is idempotent: the old block is found via its `# === Hardware
recovery functions ===` markers, removed, and rewritten — never duplicated.
`--dry-run` prints what would change without touching the file.

## Verify

```bash
./cli/check.sh              # or ./setup.sh status
```

## Notes

- Every function may prompt for sudo when it reaches the escalated steps.
- `wifi_reset` drops *all* networking for a few seconds while NetworkManager
  restarts (wired too) — expected.
- Reloads only run if the light path failed, so routine use is non-disruptive.
