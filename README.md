# Yoga 7 2-in-1 14AGP11 — Linux runbook

Everything needed to get **every** piece of this laptop working on Linux
(tested: Fedora 44 Workstation, GNOME, kernel 7.2.x) — the parts that
don't work out of the box, in one place, with one command each.

**Machine:** Lenovo Yoga 7 2-in-1 14AGP11 (83TD) · Ryzen · ALC287 audio
(`17AA:3957`) · Goodix fingerprint · WACF2200 touchscreen · Samsung
ATNA-series OLED (HDR-capable) · RTL8922AE Wi-Fi/BT.

## Quick start

```bash
./setup.sh status      # what's installed, what's missing — read-only
./setup.sh all --dry-run   # preview everything, touch nothing
./setup.sh all         # install what can be automated (asks before sudo)
```

## The modules

| Module | What it fixes | Install | Sudo? | Reboot? |
|---|---|---|---|---|
| [`cli/`](cli/) | `bt_reset`, `bt_audio_reset`, `audio_reset`, `wifi_reset` shell functions — hardware recovery that escalates only when the light fix fails | `./setup.sh cli` | on demand | no |
| [`audio/`](audio/) | Dolby Atmos speaker tuning from the Windows driver — pick a backend: EasyEffects presets (GUI) or a native PipeWire filter-chain | `./setup.sh audio [--backend easyeffects\|pipewire]` | for packages | no |
| [`fingerprint/`](fingerprint/) | `fprintd` + `libfprint` so the Goodix sensor works; enrollment is one interactive command | `./setup.sh fingerprint` | yes | no |
| [`touchscreen/`](touchscreen/) | boot-time I2C unbind/rebind so the Wacom touch + stylus register (probe-order race) | `./setup.sh touchscreen` | yes | **yes** |
| [`color-profiles/`](color-profiles/) | Windows-exported ICC profiles → `~/.local/share/icc`, assign in Settings → Color | `./setup.sh color-profiles` | no | no |
| [`hdr/`](hdr/) | patched EDID so the HDR switch appears (libdisplay-info 0.3.0), + optional mutter patch | **manual** — `./setup.sh hdr` prints the steps | yes | **yes** |

Each module has its own README: what it does, how to verify, how to undo.

## Design rules

- **One entry point.** `./setup.sh status | all | <module>`. Every module
  also has standalone `install.sh` / `check.sh` (+ `uninstall.sh` where it
  makes sense: `./setup.sh <module> --uninstall`).
- **Read-only status.** `check.sh` scripts only probe; `status` renders
  ✅ / ⚠️ / ❌ per module and exits non-zero if anything failed.
- **Dry-run first.** `--dry-run` on any command prints every action.
- **Confirmation before sudo.** Nothing privileged runs without a prompt
  (`--yes` to skip prompts; never run the scripts as root — they refuse).
- **Escalate, don't nuke.** Even the shell functions try the light fix and
  only reload kernel modules when a health check fails.
- **Pick one, switch cleanly.** The audio module has two backends
  (easyeffects / pipewire); installing one offers to remove the other,
  and `check.sh` flags a both-staged conflict instead of staying quiet.
- **Risky stays manual.** The HDR fix edits the kernel command line and
  initramfs; `setup.sh` prints instructions, never executes them.
- **No system python.** The audio converter uses a venv inside its own
  repo; only EasyEffects itself is a package install.

## Layout

```
setup.sh              orchestrator (status | all | <module> | <module> --uninstall)
lib.sh                shared helpers: logging, dry-run, confirm, pkg mgmt
cli/                  shell functions + check
audio/                converter (gitignored clone) + bundled XMLs + two backends
fingerprint/          libfprint/fprintd install + check
touchscreen/          I2C rebind service + README (manual steps kept)
color-profiles/       icc/ profiles copied from Windows
hdr/                  hdr-edid-fix (gitignored clone) + machine-specific README
tests/                test suite — see below
```

`audio/speaker-tuning-to-easyeffects/` and `hdr/hdr-edid-fix/` are
upstream git clones, excluded from this repo and auto-cloned on demand
(`./setup.sh all` or `./setup.sh hdr`), so updates come from upstream:

```bash
git -C audio/speaker-tuning-to-easyeffects pull
git -C hdr/hdr-edid-fix pull
```

## Tests

```bash
tests/run_tests.sh     # safety, idempotency, portability — no sudo, no writes
```

Covers: bash syntax of every script, `shellcheck` when available,
dry-run performs zero mutations, check scripts emit the documented line
format, `cli` install is idempotent (single block, re-runnable), no
scripted path ever reaches the HDR bootloader/initramfs edit, no
hard-coded home paths, and — for the audio backends — flag parsing
(both syntaxes, aliases, bad/missing values, no hangs), setup.sh flag
routing, route-state detection (none/one/both staged), per-backend
uninstall (removes exactly its files, idempotent, declines without
confirmation), and switch prompts that delete nothing under `--dry-run`.

## State on this machine (as of writing)

| Module | State |
|---|---|
| cli | ✅ installed (4 functions in `~/.bashrc`) |
| audio | ❌ **both backends staged** (PipeWire conf from an earlier run + EasyEffects presets) — resolve with `./setup.sh audio --backend <easyeffects\|pipewire>` (removes the other), then install EE 8 / LV2 deps |
| fingerprint | sensor detected; fingers not yet enrolled (`fprintd-enroll $USER`) |
| touchscreen | ✅ service enabled, touch working |
| color-profiles | ✅ 9/9 imported (assignment: Settings → Color) |
| hdr | ❌ fix not installed — libdisplay-info 0.3.0, fix applies; run `./setup.sh hdr` for the manual steps |

Run `./setup.sh status` for the live picture.
