# cli — hardware recovery shell functions + tab completion

Installs two marker-delimited blocks into `~/.bashrc` (both idempotent —
re-running replaces, never duplicates):

## 1. Hardware recovery functions

Four functions, each **escalating only when a post-step check fails**
(light path first, kernel-module reload as fallback):

| Function | Light steps | Escalates to | Fixes |
|---|---|---|---|
| `bt_reset` | rfkill unblock → restart BlueZ → power-cycle the controller | reload `btusb` | BlueZ wedged, adapter vanished, pairing broken |
| `bt_audio_reset` | `bt_reset` + restart PipeWire/Pulse/WirePlumber | (inherits) | BT connects but A2DP gives no audio |
| `audio_reset` | restart PipeWire/Pulse/WirePlumber | — | no speaker sound, missing default sink, xrun storms (no BT involved) |
| `wifi_reset` | `nmcli radio wifi off/on` | stop NM → reload `rtw89_8922ae` → clear rfkill | RTL8922AE firmware wedge, interface gone, scans that never return |

The escalation checks: `_bt_alive` (controller listed + powered),
`_wifi_alive` (interface present + not rfkill-blocked),
`_audio_alive` (user pipewire + wireplumber units active).

## 2. Tab completion for `./setup.sh`

Bash completion for the runbook entry point — context-aware:

- `./setup.sh <Tab>` → commands (`status all help cli fingerprint audio …`)
- `./setup.sh audio <Tab>` → common flags **plus** `--backend --variant --force`
- `./setup.sh cli <Tab>` → common flags only (audio flags don't apply)
- `./setup.sh audio --backend <Tab>` → `easyeffects pipewire ee pw`
- `./setup.sh audio --variant <Tab>` → `balanced detailed warm all`
- `--backend=<Tab>` (equals form) works too

The completion function is static (no dependency on where the runbook
lives), sourced from `completions/setup.bash` at install time.

## Install

```bash
./setup.sh cli              # or: cd cli && ./install.sh
source ~/.bashrc            # new shells get them automatically
```

Both blocks are refreshed in place on re-run. `--dry-run` prints what
would change without touching the file.

## Verify

```bash
./cli/check.sh              # or ./setup.sh status
```

## Notes

- Every function may prompt for sudo when it reaches the escalated steps.
- `wifi_reset` drops *all* networking for a few seconds while NetworkManager
  restarts (wired too) — expected.
- Reloads only run if the light path failed, so routine use is non-disruptive.
- Completion only helps after `source ~/.bashrc` (or a new terminal); if
  your shell is zsh, the functions work but the completion is bash-only.
