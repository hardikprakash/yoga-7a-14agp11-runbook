# color-profiles — ICC profiles exported from Windows

The `icc/` folder holds colour profiles copied out of the Windows
installation of this machine — mainly the panel profiles Lenovo ships
(`TPLCD_8AD6_*`: sRGB, AdobeRGB, DCIP3, DisplayP3, REC709, Native,
Default) plus `sRGB Color Space Profile.icm` and the printer profile
`RSWOP.icm`.

On a wide-gamut panel (this one is ~1.55× sRGB area), an unmanaged sRGB
desktop gets stretched across the full native gamut: punchy but wrong.
Assigning a proper profile is what makes colours *correct* rather than
*vivid*.

## Install

```bash
./setup.sh color-profiles   # copies icc/* → ~/.local/share/icc (no sudo)
```

Copy, never move: the runbook keeps pristine originals in `icc/`, and the
install is byte-identical no-ops if the files are already there.

## Assign (per display, in GNOME)

```text
Settings → Appearance → Color  →  pick the display → choose the profile
```

Headless alternative:

```bash
colormgr get-devices                                  # find the device ID
colormgr import-profile file://$HOME/.local/share/icc/TPLCD_8AD6_sRGB.icm
colormgr device-set-profile xrandr-Samsung-... <profile-id>
```

## Verify

```bash
./color-profiles/check.sh   # 9/9 profiles present + byte-identical
colormgr get-devices        # profile assignment per device
```

## Which profile when

| Profile | Use |
|---|---|
| `TPLCD_8AD6_sRGB` | everyday desktop, web content (most things assume sRGB) |
| `TPLCD_8AD6_DisplayP3` / `DCIP3` | wide-gamut photo/video work |
| `TPLCD_8AD6_AdobeRGB` | print/photography workflows |
| `TPLCD_8AD6_Native` | the panel's raw gamut — reference only, not colour-managed |
| `RSWOP.icm` | printer proofing (with the HP Ink Tank) |

See also `hdr/README.md` — "colours looking less vivid" explains why
correct colour management always looks duller than the unmanaged default.
