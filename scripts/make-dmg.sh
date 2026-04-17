#!/usr/bin/env bash
# Génère le .dmg final à partir de dist/2FujiRaw.app
# Utilise hdiutil (builtin macOS) plutôt que create-dmg pour rester sans
# dépendance et éviter les timeouts AppleScript.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/2FujiRaw.app"
DMG="$DIST/2FujiRaw.dmg"

[ -d "$APP" ] || "$ROOT/scripts/build.sh"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

# Stage : app + lien symbolique vers /Applications pour le drag & drop
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create \
    -volname "2FujiRaw" \
    -srcfolder "$STAGE" \
    -ov \
    -format UDZO \
    "$DMG" >/dev/null

SIZE="$(du -sh "$DMG" | awk '{print $1}')"
echo "Built: $DMG  ($SIZE)"
