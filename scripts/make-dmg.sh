#!/usr/bin/env bash
# Génère un .dmg distribuable à partir du .app déjà buildé.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
command -v create-dmg >/dev/null || { echo "Install create-dmg: brew install create-dmg"; exit 1; }
[ -d "$ROOT/dist/2FujiRaw.app" ] || "$ROOT/scripts/build.sh"

cd "$ROOT/dist"
rm -f 2FujiRaw.dmg
create-dmg \
    --volname "2FujiRaw" \
    --window-size 500 300 \
    --icon-size 100 \
    --icon "2FujiRaw.app" 120 150 \
    --app-drop-link 360 150 \
    --no-internet-enable \
    "2FujiRaw.dmg" \
    "2FujiRaw.app"
echo "Built: $ROOT/dist/2FujiRaw.dmg"
