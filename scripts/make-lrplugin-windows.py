#!/usr/bin/env python3
"""Assemble le module Lightroom Windows (lancé sur le runner GitHub Actions).

Produit :
  dist/2FujiRaw.lrplugin/            (les .lua + bin/windows/ + licences)
  dist/2FujiRaw-Lightroom-Windows.zip (dossier 2FujiRaw.lrplugin à la racine, comme le zip Mac)

Contrat de chemins, lu par le module Lua :
  bin\\windows\\dnglab.exe
  bin\\windows\\exiftool.exe
  bin\\windows\\exiftool_files\\

Usage : make-lrplugin-windows.py <dnglab.exe> <dossier exiftool Windows décompressé>
Le dossier exiftool est celui du zip exiftool-X.XX_64.zip : il contient
`exiftool(-k).exe` et `exiftool_files/` (ou un seul sous-dossier qui les contient).
"""
import os
import shutil
import stat
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DIST = ROOT / "dist"
PLUGIN = DIST / "2FujiRaw.lrplugin"
ZIP = DIST / "2FujiRaw-Lightroom-Windows.zip"
EXIFTOOL_EXE_NAMES = ("exiftool(-k).exe", "exiftool.exe")


def die(msg):
    print(f"Erreur : {msg}", file=sys.stderr)
    sys.exit(1)


def make_writable(root):
    """Lève la lecture seule (dossiers et fichiers issus du zip exiftool)."""
    for p in [root, *root.rglob("*")]:
        os.chmod(p, stat.S_IRWXU if p.is_dir() else stat.S_IRUSR | stat.S_IWUSR)


def find_exiftool(folder):
    """Retourne (chemin de l'exe, dossier exiftool_files) dans `folder` ou un sous-dossier direct."""
    for base in [folder] + sorted(p for p in folder.iterdir() if p.is_dir()):
        for name in EXIFTOOL_EXE_NAMES:
            exe = base / name
            files = base / "exiftool_files"
            if exe.is_file() and files.is_dir():
                return exe, files
    die(f"exiftool(-k).exe + exiftool_files/ introuvables dans {folder}")


def main(argv):
    if len(argv) != 3:
        print(__doc__, file=sys.stderr)
        return 1
    dnglab = Path(argv[1])
    exif_dir = Path(argv[2])
    if not dnglab.is_file():
        die(f"dnglab.exe introuvable : {dnglab}")
    if not exif_dir.is_dir():
        die(f"dossier exiftool introuvable : {exif_dir}")
    exif_exe, exif_files = find_exiftool(exif_dir)

    lua_files = sorted((ROOT / "lightroom" / "2FujiRaw.lrplugin").glob("*.lua"))
    if not lua_files:
        die("aucun .lua dans lightroom/2FujiRaw.lrplugin")
    for lic in ("LICENSE", "THIRD_PARTY_LICENSES.md"):
        if not (ROOT / lic).is_file():
            die(f"{lic} introuvable à la racine du dépôt")

    if PLUGIN.exists():
        make_writable(PLUGIN)
        shutil.rmtree(PLUGIN)
    ZIP.unlink(missing_ok=True)
    bin_win = PLUGIN / "bin" / "windows"
    bin_win.mkdir(parents=True)

    for f in lua_files:
        shutil.copy2(f, PLUGIN / f.name)
    shutil.copy2(dnglab, bin_win / "dnglab.exe")
    shutil.copy2(exif_exe, bin_win / "exiftool.exe")  # renommage (-k).exe -> .exe
    # copyfile : ne recopie pas les droits « lecture seule » issus du zip exiftool
    # (ils bloqueraient un rmtree ultérieur sous Windows).
    shutil.copytree(exif_files, bin_win / "exiftool_files", copy_function=shutil.copyfile)
    for lic in ("LICENSE", "THIRD_PARTY_LICENSES.md"):
        shutil.copy2(ROOT / lic, PLUGIN / lic)

    # Zip : 2FujiRaw.lrplugin/ à la racine, séparateurs « / » (norme zip).
    with zipfile.ZipFile(ZIP, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for p in sorted(PLUGIN.rglob("*")):
            if p.is_file():
                z.write(p, p.relative_to(DIST).as_posix())

    n = sum(1 for p in PLUGIN.rglob("*") if p.is_file())
    print(f"Module : {PLUGIN} ({n} fichiers)")
    print(f"Zip    : {ZIP} ({ZIP.stat().st_size / 1e6:.1f} Mo)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
