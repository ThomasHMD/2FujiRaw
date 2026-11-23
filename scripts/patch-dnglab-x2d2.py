#!/usr/bin/env python3
"""Applique le patch X2D II 100C à un clone de dnglab (idempotent, portable).

Le X2D II 100C partage le capteur du X2D 100C : deux alias dans
rawler/data/cameras/hasselblad/x2d_100c.toml suffisent. Équivalent portable
du `sed -i ''` de build-dnglab.sh (qui est propre à macOS).

Usage : patch-dnglab-x2d2.py <dossier du clone dnglab>
Codes de sortie : 0 = patch appliqué ou déjà présent, 1 = échec (ancre absente).
"""
import sys
from pathlib import Path

ANCHOR = '["Hasselblad X2D 100C", "X2D 100C"],'
ALIASES = [
    '["Hasselblad X2D II 100C", "X2D 100C"],',
    '["X2D II 100C", "X2D 100C"],',
]
CAM_TOML = Path("rawler/data/cameras/hasselblad/x2d_100c.toml")


def main(argv):
    if len(argv) != 2:
        print(__doc__, file=sys.stderr)
        return 1
    path = Path(argv[1]) / CAM_TOML
    if not path.is_file():
        print(f"Erreur : {path} introuvable.", file=sys.stderr)
        return 1
    # newline="" : on garde les fins de ligne du fichier (LF ou CRLF).
    with open(path, encoding="utf-8", newline="") as f:
        text = f.read()
    if "X2D II 100C" in text:
        print("Patch : déjà appliqué, rien à faire.")
        return 0
    eol = "\r\n" if "\r\n" in text else "\n"
    lines = text.split(eol)
    for i, line in enumerate(lines):
        if line.strip() == ANCHOR:
            indent = line[: len(line) - len(line.lstrip())]
            lines[i + 1:i + 1] = [indent + a for a in ALIASES]
            break
    else:
        print(f"Erreur : ligne d'ancrage {ANCHOR} absente de {path} (format amont changé ?).",
              file=sys.stderr)
        return 1
    with open(path, "w", encoding="utf-8", newline="") as f:
        f.write(eol.join(lines))
    print(f"Patch : alias X2D II 100C ajoutés dans {path}.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
