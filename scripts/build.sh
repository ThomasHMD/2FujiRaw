#!/usr/bin/env bash
# Compile le binaire Swift, assemble le .app, bundle les outils vendor, codesign ad-hoc.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/2FujiRaw.app"

# 1. Fetch deps si absentes
[ -f "$ROOT/vendor/dnglab" ] || "$ROOT/scripts/fetch-deps.sh"

# 2. Build Swift release arm64
echo "Building Swift executable..."
cd "$ROOT/src"
swift build -c release --arch arm64

# 3. Assembler l'app bundle
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources/bin"
mkdir -p "$APP/Contents/Resources/templates"

cp "$ROOT/src/.build/release/ToFujiRaw" "$APP/Contents/MacOS/2FujiRaw"
cp "$ROOT/vendor/dnglab" "$APP/Contents/Resources/bin/dnglab"
cp -R "$ROOT/vendor/exiftool" "$APP/Contents/Resources/bin/exiftool"
cp "$ROOT/vendor/hasselblad_x2d_header.3fr" "$APP/Contents/Resources/templates/hasselblad_x2d_header.3fr"

# Les outils copiés depuis Dropbox/téléchargements arrivent souvent avec
# `com.apple.quarantine`, ce qui bloque leur exécution depuis l'app.
xattr -dr com.apple.quarantine "$APP" || true

# 4. Écrire Info.plist
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>2FujiRaw</string>
    <key>CFBundleDisplayName</key><string>2FujiRaw</string>
    <key>CFBundleExecutable</key><string>2FujiRaw</string>
    <key>CFBundleIdentifier</key><string>com.thomashmd.twofujiraw</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# 5. Copier l'icône (optionnel tant qu'elle n'existe pas)
[ -f "$ROOT/src/Sources/ToFujiRaw/Resources/AppIcon.icns" ] && \
    cp "$ROOT/src/Sources/ToFujiRaw/Resources/AppIcon.icns" "$APP/Contents/Resources/"

# 6. Codesign ad-hoc (pour que Gatekeeper accepte après "clic droit > Ouvrir")
echo "Ad-hoc codesigning..."
codesign --force --deep --sign - "$APP"

echo "Built: $APP"
