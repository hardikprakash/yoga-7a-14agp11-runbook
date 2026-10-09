# hdr — HDR on this laptop (EDID + mutter)

The tool: [Boogie61/hdr-edid-fix](https://github.com/Boogie61/hdr-edid-fix),
cloned into `hdr/hdr-edid-fix/` (gitignored; re-cloned by the installer if
missing). This README records **what applies to this specific machine**
and how to run the fix safely.

## Status on the Yoga 7 14AGP11 (checked by `./hdr/check.sh`)

| Problem | Applies here? | Why |
|---|---|---|
| **1. No HDR switch at all** | **Yes** — Fedora 44 ships libdisplay-info **0.3.0**; the panel (Samsung ATNA-series) hides HDR metadata inside a *DisplayID* block that only 0.4.0+ reads | fixed by patching the EDID |
| **2. HDR on but washed out** | **Yes** — GNOME/mutter sends `HDR_OUTPUT_METADATA` with PQ set but all mastering fields zero | fixed by the mutter patch (optional) |

Check the live state any time:

```bash
./hdr/check.sh              # part of ./setup.sh status as well
```

## Why this is never automated

`hdr-edid-fix/install.sh` rewrites:
- `/usr/lib/firmware/edid/hdr-patched-edid.bin`
- the **kernel command line** (`drm.edid_firmware=eDP-1:...`) in GRUB/limine
- the **initramfs** config (the file must be in there, or the DRM driver
  loads before the patch exists)

A bad edit here means a black panel at boot. It's a one-command fix
*with a known escape hatch*, so it stays manual. `./setup.sh hdr` prints
these steps but runs none of them.

## Install (manual, step by step)

```bash
./setup.sh hdr                                          # shows status + the steps
cd hdr/hdr-edid-fix

./edid/patch-edid.py --check                            # must report an HDR block
sudo ./install.sh                                       # EDID + cmdline + initramfs
sudo reboot
./check.sh                                              # full 5-step chain walk
```

`install.sh` handles mkinitcpio/dracut and limine/GRUB/`/etc/kernel/cmdline`,
and backs up whatever it edits (`*.hdr-backup`). If it can't find your
bootloader it prints the parameter to add by hand.

### If the panel stays dark at boot

Edit the bootloader entry once and drop `drm.edid_firmware=...` — or:

```bash
sudo ./uninstall.sh        # removes param + firmware + regenerates initramfs
```

## Problem 2 — washed-out HDR (GNOME, optional)

Until [mutter!5199](https://gitlab.gnome.org/GNOME/mutter/-/merge_requests/5199)
lands, GNOME sends no mastering metadata and the panel tone-maps blindly.
Patch file: `hdr/hdr-edid-fix/mutter/hdr-mastering-metadata.patch`
(applies to mutter 50.x). Building a patched mutter on Fedora means
rebuilding the `mutter` RPM — invasive, overwritten by every update, and
purely cosmetic, hence **documented, not scripted**. KWin fills the fields
in already, so KDE users can ignore this.

Verify what the compositor is actually programming (HDR on):

```bash
cd hdr/hdr-edid-fix && ./infoframe.sh
```

You want EOTF=PQ *and* populated mastering fields.

## Requirements / verify the panel really does HDR

```bash
mpv --vo=gpu-next --gpu-api=vulkan --loop=inf --fullscreen hdr/hdr-edid-fix/test/hdr-test.mp4
```

The 600 vs 1000 nit patches must look clearly different (SDR: they merge).

Full documentation: `hdr/hdr-edid-fix/README.md` (upstream, CC0).
