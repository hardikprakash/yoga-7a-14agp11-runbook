# audio — Dolby Atmos speaker tuning for Linux

Brings this laptop's Windows speaker tuning (Dolby DAX3) to Linux: the
tuning XML that shipped in the Lenovo Windows audio driver is converted
into an active audio chain — speaker correction FIR, EQ, multiband
compression, limiter — at zero added latency.

The converter is [antoinecellerier/speaker-tuning-to-easyeffects](https://github.com/antoinecellerier/speaker-tuning-to-easyeffects),
cloned into `speaker-tuning-to-easyeffects/` (gitignored here; re-cloned
by the installer if missing).

## Choose a backend

The same tuning can run two ways. **Pick one — both must never be active
at once**, or the audio gets processed twice (echoey, over-compressed).

| | `--backend easyeffects` (default) | `--backend pipewire` |
|---|---|---|
| Runs as | EasyEffects 8 presets + autoload | native `pipewire.conf.d` filter-chain |
| GUI | yes — switch Balanced/Detailed/Warm live | no — set-and-forget |
| Extra process | EasyEffects daemon (~270 MB) | none (~78 MB) |
| Needs installed | EasyEffects 8 | LSP + Calf LV2 plugins (+ lilv) |
| Voicings | all three, switchable in the GUI | one at a time, via `--variant` |
| CPU/RAM | baseline | ~11% fewer cycles, ~3.5× less RAM |
| Latency | zero (minimum-phase FIR) | zero |

```bash
./setup.sh audio                              # easyeffects (default)
./setup.sh audio --backend pipewire           # native, no GUI
./setup.sh audio --backend pw --variant warm  # aliases + voicing (pipewire only)
```

Switching is clean: when the *other* backend's files are staged, the
installer prompts to remove them first (declining keeps them, but warns
loudly about double-processing).

## The XML in `xml/`

| File | What it is |
|---|---|
| `DEV_0287_SUBSYS_17AA3957_PCI_SUBSYS_38F417AA.xml` | **The right one for this machine** — exact match for the Realtek ALC287 with codec subsystem `17AA:3957` (PCI subsystem `17AA:38F4`), exported from the Windows driver |
| `Speaker_Default_Atmos3.8.xml` | generic Atmos 3.8 default — a fallback, sounds noticeably wrong on this codec |

The installer picks the `DEV_0287_SUBSYS_17AA3957*` match automatically.

## Install

```bash
./setup.sh audio [--backend <name>] [--variant <name>]
```

What it does, in order:

1. clones the converter repo (skip if already present)
2. creates/repairs a `.venv` **inside the repo** — no system-python
   packages ever, and a venv left over from a moved folder is detected
   and recreated
3. `pip install -r requirements.txt` into that venv
4. backend dependencies:
   - **easyeffects** → EasyEffects 8 via the distro package (Fedora 44
     ships 8.2.8; if yours only has 7.x use the Flatpak — EE 7 and 8
     preset formats are incompatible)
   - **pipewire** → `lsp-plugins-lv2` + `lv2-calf-plugins` + `lilv`
     (Fedora names; mapped for apt/pacman/zypper too) and `pw-dump` if
     missing — installed automatically, asked before sudo
5. if the other backend is staged: prompt to remove it, then run the
   chosen converter against the bundled XML — `--autoload` (easyeffects)
   or activate the filter-chain with a PipeWire restart (pipewire)

### After the easyeffects install (manual, GUI)

EasyEffects → preferences → enable **Background Service** and
**Autostart**. Without these the preset is gone after logout.

### Changing the voicing (pipewire backend)

```bash
./setup.sh audio --backend pipewire --variant detailed   # or warm
```

## Remove / switch (reversible)

```bash
./setup.sh audio --uninstall                    # remove both routes
./setup.sh audio --uninstall --backend pipewire # remove one route only
./audio/uninstall.sh --dry-run                  # list what would go
```

User-level only, no sudo: deletes the `Dolby-*` presets/impulses/autoload
entries (easyeffects, native + Flatpak) or the `Dolby_*.conf` + `.irs`
filter-chain files (pipewire, then restarts your user PipeWire to unload
the chain). The easyeffects/LV2 **packages stay installed** — other
things may use them. Reinstall with `./setup.sh audio --backend <name>`.

Declining the confirmation removes nothing (and piping `y` doesn't count —
non-interactive runs need `--yes`).

## Verify

```bash
./audio/check.sh             # which backend is staged, active, conflicted
# full doctor (read-only, deeper) — route specific:
audio/speaker-tuning-to-easyeffects/.venv/bin/python \
    audio/speaker-tuning-to-easyeffects/dolby_to_easyeffects.py --doctor
audio/speaker-tuning-to-easyeffects/.venv/bin/python \
    audio/speaker-tuning-to-easyeffects/dolby_to_pipewire.py --doctor
```

A/B test (easyeffects): toggle the preset off/on in the GUI; make sure
the global bypass (power-button icon in the top bar) is OFF.

## Undo

Use `./setup.sh audio --uninstall` (above). For the manual file list,
see the upstream docs: `speaker-tuning-to-easyeffects/docs/dolby-to-easyeffects.md#undo`.

## Troubleshooting

- **check.sh says "both routes staged"** → you (or a previous run) left
  files from both backends. Remove one: `./setup.sh audio --uninstall
  --backend <the one you don't want>`.
- **No audible difference** → run the `--doctor` command for your route;
  then check the global bypass and desktop volume.
- **Quieter than Windows** → easyeffects: add `--enable autogain` to the
  converter run; pipewire: see the upstream `dolby_to_pipewire.py --help`.
- **PipeWire route inactive after install** → `./audio/check.sh` says
  "NOT loaded"; restart: `systemctl --user restart pipewire pipewire-pulse`.
- **Wrong/odd sound** → you're on the generic XML; re-export the driver
  XML for codec `17AA:3957` (see `docs/getting-the-xml.md` in the repo,
  or `tools/fetch_driver/get_lenovo_dax_xml.py` — needs `innoextract`).
