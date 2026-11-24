**English** | [Français](README.fr.md)

# 2FujiRaw

> **New, v0.3.0 (24/11/2026): the Lightroom Classic plug-in now runs on
> Windows (beta), and an exposure fix.** The plug-in carries its own tools and
> needs no app on Windows (Hasselblad `.3FR` / `.FFF` only). The fix: on some
> photos, the Fuji DNGs came out up to 2 EV darker than the original in
> Lightroom. DNGs converted with 0.2.0 from such photos should be redone.
> ➜ [Download v0.3.0](https://github.com/ThomasHMD/2FujiRaw/releases/tag/v0.3.0) ·
> [Windows](#windows-beta) · [Exposure fix](#exposure-correction)

A macOS app (and a Lightroom Classic plug-in for macOS and Windows) that converts RAW files from non-Fuji cameras into DNGs "disguised"
as a **Fuji GFX 100S II**, to unlock the **native Fujifilm Film Simulations**
(Provia, Velvia, Astia, Classic Chrome, Classic Neg, Eterna, Acros, Pro Neg
Hi/Std, Nostalgic Neg, Reala Ace…) in Lightroom Classic.

Available conversions:
- `Hasselblad X2D II 100C → Fuji GFX 100S II`
- `Leica DNG → Fuji GFX 100S II`
- `Leica DNG → Hasselblad X2D`

The Leica conversion is a contribution from [smartfuse](https://github.com/smartfuse)
([request no. 1](https://github.com/ThomasHMD/2FujiRaw/pull/1)).

---

## Download

### ➜ [**2FujiRaw.dmg** (latest release)](https://github.com/ThomasHMD/2FujiRaw/releases/latest/download/2FujiRaw.dmg)

~20 MB · macOS 13+ · Apple Silicon (arm64) · ad-hoc signed

### ➜ [**2FujiRaw-Lightroom.zip**, the Lightroom Classic plug-in](https://github.com/ThomasHMD/2FujiRaw/releases/latest/download/2FujiRaw-Lightroom.zip)

~15 MB · the same conversion from Lightroom, app included (see [Lightroom Classic plug-in](#lightroom-classic-plug-in))

### ➜ [**2FujiRaw-Lightroom-Windows.zip**, the Lightroom Classic plug-in for Windows (beta)](https://github.com/ThomasHMD/2FujiRaw/releases/latest/download/2FujiRaw-Lightroom-Windows.zip)

The same plug-in for Windows, with its own tools, no app needed (see [Windows (beta)](#windows-beta))

See all versions and their changelog in
[Releases](https://github.com/ThomasHMD/2FujiRaw/releases) ·
[Latest release](https://github.com/ThomasHMD/2FujiRaw/releases/latest).

The **source code** is this very repo, licensed GPL-3.0-or-later, see
[`LICENSE`](./LICENSE).

---

## Why

Fuji Film Simulations are not `.dcp` files on disk: they are hardcoded in Adobe's
Camera Raw plug-in and applied automatically when Lightroom detects a file from a
Fuji camera. The filter relies on the `Make` / `Model` / `UniqueCameraModel` tags
of the RAW.

When a Hasselblad `.3FR` is converted to **DNG** (a standard TIFF format),
Lightroom loses the link to the proprietary Hasselblad parser and relies only on
the TIFF tags. They can therefore be spoofed to point to an equivalent Fuji
camera.

**Why the GFX 100S II and not an X-T5?** The Hasselblad X2D II 100C and the Fuji
GFX 100S II physically share the **same Sony IMX461 sensor** (100 MP, Bayer
demosaicing). The spoof is therefore transparent to Camera Raw's demosaicing
engine. Spoofing to an X-T5 would force **X-Trans** demosaicing (a different one)
onto **Bayer** data → guaranteed artifacts.

## How it works

```
Hasselblad X2D / X2D II .3FR
      │
      ▼  [1] dnglab convert (patched for X2D II 100C)
.dng Hasselblad
      │
      ▼  [2] exiftool: Fuji spoof
.dng Fuji GFX 100S II

Leica .DNG
      │
      ▼  [1] native Swift writer: Leica → X2D .3FR
.3fr Hasselblad X2D
      │
      ├── direct Hasselblad output
      │
      ▼  [2] dnglab convert + Fuji spoof
.dng Fuji GFX 100S II
```

The Fuji DNGs are then imported into Lightroom Classic: the native Fuji profiles
show up in the "Camera Matching" tab.

The `dnglab` and `exiftool` binaries are bundled in the `.app` and called as
subprocesses. The Leica → X2D chain is native Swift.

### Exposure correction

The X2D II stores in each `.3FR` an exposure correction specific to the photo
(the DNG tag `BaselineExposure`, up to +2 EV). dnglab does not copy it, so on
those photos the Fuji DNGs came out up to 2 EV darker than the original in
Lightroom. Since v0.3.0, exiftool copies it back from the original RAW, on Mac
and on Windows. **DNGs converted with 0.2.0 from such photos should be redone.**

### Bundled X2D template

Leica conversions no longer need an external `.3FR` donor. The app bundles an X2D
template truncated to its useful header
(`Contents/Resources/templates/hasselblad_x2d_header.3fr`, 16 KiB) and uses it by
default. The `--donor` option on the CLI side, and the donor picker in the UI,
only serve as an override.

### Why a patched dnglab

The official `dnglab 0.7.2` only recognizes the **X2D 100C** (2022), not the
**X2D II 100C** (2024). Since both cameras share the same sensor, I simply add two
alias lines in `rawler/data/cameras/hasselblad/x2d_100c.toml` and recompile. The
`scripts/build-dnglab.sh` script does this automatically (clone v0.7.2 → patch →
cargo build → copy into `vendor/`).

## Installation (end user)

1. Download the `.dmg` from the latest [GitHub release](https://github.com/ThomasHMD/2FujiRaw/releases).
2. Double-click it: macOS mounts a window with the `2FujiRaw.app` icon and an
   `Applications` shortcut.
3. **Drag `2FujiRaw.app` onto `Applications`**.
4. Eject the `.dmg` (right-click → "Eject"), you can delete it.

### First launch

The app is signed **ad-hoc** (no Apple Developer account). On first launch, macOS
shows:

> *"2FujiRaw" can't be opened because the developer cannot be verified.*

To get around it, once only:

1. Open `/Applications` in the Finder.
2. **Right-click** `2FujiRaw.app` → `Open`.
3. Click `Open` again in the confirmation window.

Later launches work normally (double-click, Launchpad, Spotlight).

## Lightroom Classic plug-in

The same conversion, without leaving Lightroom: **Library ▸ Plug-in Extras ▸
Convert to Fuji GFX 100S II…** (also in **File ▸ Plug-in Extras**), on the
selected photos.

- Takes Hasselblad `.3FR` / `.FFF` and Leica `.DNG` files; the rest of the
  selection is left aside (the summary says why).
- The Fuji DNG is written next to the original and enters the catalog,
  **stacked above it** (Lightroom only stacks within one folder). With the stack
  option unchecked, it goes into `DNG-Fuji-Converted/`, as with the app.
- Carries over keywords, collections, rating, flag, label, title, caption, and
  the original's **Develop settings** (can be unchecked), **except the profile**.
- Optionally applies a develop **preset**. For a Fuji simulation by default: a
  preset with only the profile ticked (Classic Chrome…), or Preferences ▸ Presets
  ▸ Raw Defaults ▸ GFX 100S II, which Lightroom then applies by itself on every
  import.

**Installation**: download `2FujiRaw-Lightroom.zip` from the
[latest release](https://github.com/ThomasHMD/2FujiRaw/releases/latest), unzip
it, then File ▸ Plug-in Manager ▸ Add ▸ `2FujiRaw.lrplugin`. The plug-in ships
with its own copy of the app (no need to install the `.dmg`) and lifts the macOS
quarantine itself on first use. Apple Silicon Mac, Lightroom Classic 10 or
newer (for Windows, see below).

On a failure, the message gives the path of a diagnostic log, `2FujiRaw.log`
(on Mac as well as on Windows).

Without an embedded copy, the plug-in looks for the app in `/Applications`, then
`~/Applications`, or at the path set in the Plug-in Manager.

The sources are in [`lightroom/`](./lightroom): `Convertir.lua` (window and loop),
`Conversion.lua` (one photo), `Outil.lua` (CLI call), `Regles.lua` (the
decisions, SDK-free). The Lightroom SDK has no entry point in the import: the
conversion runs afterwards.

### Windows (beta)

The plug-in also runs on Windows, in beta: download
[`2FujiRaw-Lightroom-Windows.zip`](https://github.com/ThomasHMD/2FujiRaw/releases/latest/download/2FujiRaw-Lightroom-Windows.zip)
from the [latest release](https://github.com/ThomasHMD/2FujiRaw/releases/latest).
There is no app on Windows: the plug-in bundles `dnglab.exe` (0.7.2 with the X2D
II patch, built by GitHub Actions on `windows-latest`, workflow
[`windows.yml`](./.github/workflows/windows.yml)) and ExifTool for Windows.

1. Unzip the file.
2. In Lightroom Classic: File ▸ Plug-in Manager ▸ Add ▸ the `2FujiRaw.lrplugin`
   folder.
3. Click **Test the tools** ("Tester les outils" in the French interface): it
   shows the versions of dnglab and ExifTool found.

Limits of the beta:
- Hasselblad `.3FR` / `.FFF` only; **Leica stays Mac only**.
- The menu label stays in French: **Convertir en Fuji GFX 100S II…**
- On a failure, the message gives the path of a `2FujiRaw.log` file: send it with
  your report.
- Tested on the Windows CI (end-to-end conversion, accented paths) and by a first
  user on Windows 11.

## Build from source (dev)

Requirements:
- macOS 13+ on Apple Silicon (arm64)
- Swift 5.9+ (shipped with the Xcode Command Line Tools)
- [Rust + cargo](https://rustup.rs) (to compile the patched dnglab)
- `unzip`, `curl`, `hdiutil` (already on macOS, zero third-party dependency for
  the `.dmg`)

```bash
# 1. Fetch dependencies (builds patched dnglab + downloads portable exiftool)
./scripts/fetch-deps.sh

# 2. Build the app (Swift release build + assembles the .app + ad-hoc codesign)
./scripts/build.sh

# 3. Test from the CLI, no GUI
./src/.build/release/ToFujiRaw --cli --mapping hassy-x2d2-to-fuji-gfx100s2 /path/to/mon_fichier.3FR
./src/.build/release/ToFujiRaw --cli --mapping leica-dng-to-hasselblad-x2d2 /path/to/mon_fichier.DNG
./src/.build/release/ToFujiRaw --cli --mapping leica-dng-to-fuji-gfx100s2 /path/to/mon_fichier.DNG

# 4. Build the final .dmg
./scripts/make-dmg.sh

# 5. Lightroom plug-in: dist/2FujiRaw.lrplugin + dist/2FujiRaw-Lightroom.zip
#    (--installer: also copies it into this Mac's Lightroom plug-ins)
./scripts/make-lrplugin.sh

# Plug-in checks: rules only, then the whole plug-in on a simulated SDK
# with the real app, on a COPY of a .3FR
lua lightroom/tests/test_hors_lr.lua
lua lightroom/tests/test_avec_cli.lua /chemin/copie.3FR "$PWD/dist/2FujiRaw.app"
```

Test in the real Lightroom, headless: `lightroom/tests/essai_lightroom.py` goes
through a test plug-in that runs Lua sent by file (the one from SpektraLR on my
machine), imports the copy of a `.3FR`, converts it, reads back what Lightroom
sees (Fujifilm GFX 100S II, default PROVIA profile, stack, rating, keyword,
collection, settings) and exports one JPEG per simulation. Passed on 14/11/2026
on Lightroom Classic 16.0.

The `--donor` flag remains available if you want to override the bundled X2D
template:

```bash
./src/.build/release/ToFujiRaw --cli \
  --mapping leica-dng-to-hasselblad-x2d2 \
  --donor /path/to/custom_donor.3FR \
  /path/to/mon_fichier.DNG
```

## License

2FujiRaw is distributed under **GPL-3.0-or-later** (see [`LICENSE`](./LICENSE)).

This choice is needed because the `.dmg` bundles **dnglab** (LGPL-2.1) and
**exiftool** (Artistic / GPL): GPL-3 is the simplest license that stays
compatible with both while ensuring that any redistributed modification remains
free.

The full licenses of the embedded third-party dependencies are in
[`THIRD_PARTY_LICENSES.md`](./THIRD_PARTY_LICENSES.md).

## Disclaimer

Independent project, **not affiliated** with Adobe, Fujifilm or Hasselblad. The
trademarks "Fujifilm", "GFX 100S II", "Hasselblad", "X2D II 100C", "Lightroom"
and the names of Film Simulations (Provia, Velvia, Classic Chrome, etc.) belong
to their respective owners.

2FujiRaw does **not redistribute any code or profile** belonging to Adobe,
Fujifilm or Hasselblad. It only:
- converts your own RAW files to DNG (via dnglab, LGPL)
- rewrites the standard TIFF tags of these DNGs (via exiftool, Artistic/GPL)

Use at your own risk, in accordance with the terms of use of the software you use
to open the produced DNGs.

## References

- Original method (DNG spoofing to unlock Fuji profiles):
  [rbrant.substack.com](https://rbrant.substack.com/p/how-to-use-fujifilm-profiles-with)
- [dnglab](https://github.com/dnglab/dnglab): RAW → DNG converter
- [ExifTool](https://exiftool.org/): metadata reading / writing
- [Adobe DNG 1.4 spec](https://helpx.adobe.com/photoshop/digital-negative.html)
