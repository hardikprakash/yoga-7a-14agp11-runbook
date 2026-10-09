# audio — Dolby Atmos speaker tuning for Linux

Brings this laptop's Windows speaker tuning (Dolby DAX3) to Linux: the
tuning XML that shipped in the Lenovo Windows audio driver is converted
into EasyEffects presets — speaker correction FIR, EQ, multiband
compression, limiter — at zero added latency.

The converter is [antoinecellerier/speaker-tuning-to-easyeffects](https://github.com/antoinecellerier/speaker-tuning-to-easyeffects),
cloned into `speaker-tuning-to-easyeffects/` (gitignored here; re-cloned
by the installer if missing).

## The XML in `xml/`

| File | What it is |
|---|---|
| `DEV_0287_SUBSYS_17AA3957_PCI_SUBSYS_38F417AA.xml` | **The right one for this machine** — exact match for the Realtek ALC287 with codec subsystem `17AA:3957` (PCI subsystem `17AA:38F4`), exported from the Windows driver |
| `Speaker_Default_Atmos3.8.xml` | generic Atmos 3.8 default — a fallback, sounds noticeably wrong on this codec |

The installer picks the `DEV_0287_SUBSYS_17AA3957*` match automatically.

## Install

```bash
./setup.sh audio
```

What it does, in order:

1. clones the converter repo (skip if already present)
2. creates/repairs a `.venv` **inside the repo** — no system-python
   packages ever, and a venv left over from a moved folder is detected
   and recreated
3. `pip install -r requirements.txt` into that venv
4. installs EasyEffects 8 via the distro package (Fedora 44 ships 8.2.8;
   if your distro only has 7.x use the Flatpak instead — EE 7 and 8
   preset formats are incompatible)
5. runs `dolby_to_easyeffects.py <bundled XML> --autoload` → generates
   `Dolby-Balanced/Detailed/Warm` and wires autoload for the speakers

## Make it survive reboot (manual, GUI)

EasyEffects → preferences → enable **Background Service** and
**Autostart**. Without these the preset is gone after logout.

## Verify

```bash
./audio/check.sh             # repo, venv, presets, autoload, EE version
# full doctor (read-only, deeper):
audio/speaker-tuning-to-easyeffects/.venv/bin/python \
    audio/speaker-tuning-to-easyeffects/dolby_to_easyeffects.py --doctor
```

A/B test: in EasyEffects toggle the preset off/on; make sure the global
bypass (power-button icon in the top bar) is OFF.

## Undo

Presets and autoload are user-level only:

```bash
rm ~/.local/share/easyeffects/output/Dolby-*.json
rm ~/.local/share/easyeffects/autoload/output/*.json   # if created
```

## Troubleshooting

- **No audible difference** → run the `--doctor` command above; then check
  the global bypass and desktop volume.
- **Quieter than Windows** → add `--enable autogain` to the converter run.
- **Wrong/odd sound** → you're on the generic XML; re-export the driver
  XML for codec `17AA:3957` (see `docs/getting-the-xml.md` in the repo,
  or `tools/fetch_driver/get_lenovo_dax_xml.py` — needs `innoextract`).
