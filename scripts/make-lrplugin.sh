#!/usr/bin/env bash
# Assemble le module Lightroom autonome : dist/2FujiRaw.lrplugin (les .lua + l'app embarquée dans bin/),
# puis dist/2FujiRaw-Lightroom.zip pour la release.
#   --installer : copie aussi le module dans les modules externes de Lightroom de ce Mac
#                 (~/Library/Application Support/Adobe/Lightroom/Modules), où Lightroom le charge seul.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/2FujiRaw.app"
PLUGIN="$ROOT/dist/2FujiRaw.lrplugin"
ZIP="$ROOT/dist/2FujiRaw-Lightroom.zip"
MODULES="$HOME/Library/Application Support/Adobe/Lightroom/Modules"

[ -x "$APP/Contents/MacOS/2FujiRaw" ] || "$ROOT/scripts/build.sh"

# Contrôles avant d'empaqueter
for f in "$ROOT"/lightroom/2FujiRaw.lrplugin/*.lua; do luac -p "$f"; done
lua "$ROOT/lightroom/tests/test_hors_lr.lua"

rm -rf "$PLUGIN" "$ZIP"
mkdir -p "$PLUGIN/bin"
cp "$ROOT"/lightroom/2FujiRaw.lrplugin/*.lua "$PLUGIN/"
ditto "$APP" "$PLUGIN/bin/2FujiRaw.app"
cp "$ROOT/LICENSE" "$ROOT/THIRD_PARTY_LICENSES.md" "$PLUGIN/"
xattr -dr com.apple.quarantine "$PLUGIN" 2>/dev/null || true

(cd "$ROOT/dist" && ditto -c -k --keepParent "2FujiRaw.lrplugin" "$(basename "$ZIP")")
echo "Module : $PLUGIN"
echo "Zip    : $ZIP ($(du -h "$ZIP" | cut -f1))"

if [ "${1:-}" = "--installer" ]; then
    mkdir -p "$MODULES"
    rm -rf "$MODULES/2FujiRaw.lrplugin"
    ditto "$PLUGIN" "$MODULES/2FujiRaw.lrplugin"
    echo "Installé : $MODULES/2FujiRaw.lrplugin (redémarrer Lightroom s'il est ouvert)"
fi
