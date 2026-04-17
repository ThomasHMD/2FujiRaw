#!/usr/bin/env bash
# Télécharge dnglab + exiftool portables dans vendor/.
# À relancer seulement pour bump les versions.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/vendor"
mkdir -p "$VENDOR"

# -- dnglab (arm64) --
# Le binaire officiel v0.7.2 ne supporte pas le Hasselblad X2D II 100C.
# On compile une version patchée depuis les sources (cf build-dnglab.sh).
echo "Building patched dnglab from sources..."
"$ROOT/scripts/build-dnglab.sh"

# -- exiftool (portable) --
# Récupère dynamiquement la dernière version publiée sur exiftool.org
EXIF_VERSION="$(curl -sL https://exiftool.org/ver.txt | tr -d '[:space:]')"
EXIF_URL="https://exiftool.org/Image-ExifTool-${EXIF_VERSION}.tar.gz"
echo "Fetching exiftool ${EXIF_VERSION}..."
curl -fL "$EXIF_URL" -o /tmp/exiftool.tar.gz
rm -rf "$VENDOR/exiftool"
mkdir -p "$VENDOR/exiftool"
tar -xzf /tmp/exiftool.tar.gz -C "$VENDOR/exiftool" --strip-components=1

echo "Vendor ready:"
ls -la "$VENDOR"
