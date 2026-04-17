#!/usr/bin/env bash
# Génère l'icône .icns de l'app à partir de rien, avec du Swift one-shot.
# Style cohérent avec l'UI : squircle crème, bordure violette foncée, gros "2FR"
# magenta en monospace bold, petit chevron cyan pour le côté "transform".
#
# Prérequis : swift + sips + iconutil (tous builtin macOS).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_PNG="/tmp/2fujiraw-icon-1024.png"
ICONSET="/tmp/2fujiraw.iconset"
OUT_ICNS="$ROOT/src/Sources/ToFujiRaw/Resources/AppIcon.icns"

# --- 1. Générer le PNG 1024×1024 en Swift one-shot -------------------------
SWIFT_SCRIPT="$(mktemp -t 2fujiraw-icon-XXXXXX).swift"
cat > "$SWIFT_SCRIPT" <<'SWIFT'
import AppKit
import CoreGraphics
import Foundation

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

// Palette (même que Theme.swift)
let cream    = NSColor(calibratedRed: 0.98, green: 0.95, blue: 0.88, alpha: 1)
let peach    = NSColor(calibratedRed: 0.99, green: 0.88, blue: 0.78, alpha: 1)
let magenta  = NSColor(calibratedRed: 0.98, green: 0.24, blue: 0.55, alpha: 1)
let cyan     = NSColor(calibratedRed: 0.27, green: 0.82, blue: 0.87, alpha: 1)
let ink      = NSColor(calibratedRed: 0.15, green: 0.11, blue: 0.28, alpha: 1)

let ctx = NSGraphicsContext.current!.cgContext

// Squircle arrondi (style icône macOS moderne)
let inset: CGFloat = 60
let radius: CGFloat = 220
let rect = NSRect(x: inset, y: inset, width: size - 2*inset, height: size - 2*inset)

// Ombre portée "hard" magenta décalée (style pixel-art)
let shadowPath = NSBezierPath(roundedRect: rect.offsetBy(dx: 18, dy: -18),
                              xRadius: radius, yRadius: radius)
magenta.setFill()
shadowPath.fill()

// Fond principal : gradient crème → pêche
let bgPath = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
ctx.saveGState()
bgPath.addClip()
let gradient = NSGradient(colors: [cream, peach])!
gradient.draw(in: rect, angle: 270)
ctx.restoreGState()

// Bordure épaisse violet foncé
ink.setStroke()
bgPath.lineWidth = 22
bgPath.stroke()

// Gros "2FR" en monospace bold magenta, centré
let title = "2FR"
let titleFont = NSFont.monospacedSystemFont(ofSize: 460, weight: .bold)
let titleAttrs: [NSAttributedString.Key: Any] = [
    .font: titleFont,
    .foregroundColor: magenta,
    .kern: -12,
]
let titleStr = NSAttributedString(string: title, attributes: titleAttrs)
let titleSize = titleStr.size()
let titleRect = NSRect(
    x: (size - titleSize.width) / 2,
    y: (size - titleSize.height) / 2 + 60,
    width: titleSize.width,
    height: titleSize.height
)
titleStr.draw(in: titleRect)

// Sous-titre : "→ FUJI" en monospace cyan en bas
let subtitle = "→ FUJI"
let subFont = NSFont.monospacedSystemFont(ofSize: 98, weight: .semibold)
let subAttrs: [NSAttributedString.Key: Any] = [
    .font: subFont,
    .foregroundColor: cyan,
    .kern: 4,
]
let subStr = NSAttributedString(string: subtitle, attributes: subAttrs)
let subSize = subStr.size()
let subRect = NSRect(
    x: (size - subSize.width) / 2,
    y: 180,
    width: subSize.width,
    height: subSize.height
)
subStr.draw(in: subRect)

// Petit liseré décoratif (scanline rétro) en haut
let scanRect = NSRect(x: inset + 40, y: size - inset - 100, width: size - 2*inset - 80, height: 4)
cyan.setFill()
NSBezierPath(rect: scanRect).fill()

image.unlockFocus()

let tiff = image.tiffRepresentation!
let bitmap = NSBitmapImageRep(data: tiff)!
let png = bitmap.representation(using: .png, properties: [:])!
let outPath = CommandLine.arguments[1]
try png.write(to: URL(fileURLWithPath: outPath))
SWIFT

swift "$SWIFT_SCRIPT" "$OUT_PNG"
rm -f "$SWIFT_SCRIPT"

# --- 2. Générer toutes les résolutions requises pour un .icns --------------
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

# Toutes les paires (taille, scale) attendues par iconutil
declare -a SIZES=(
    "16 icon_16x16.png"
    "32 icon_16x16@2x.png"
    "32 icon_32x32.png"
    "64 icon_32x32@2x.png"
    "128 icon_128x128.png"
    "256 icon_128x128@2x.png"
    "256 icon_256x256.png"
    "512 icon_256x256@2x.png"
    "512 icon_512x512.png"
    "1024 icon_512x512@2x.png"
)

for entry in "${SIZES[@]}"; do
    s="${entry%% *}"
    n="${entry##* }"
    sips -z "$s" "$s" "$OUT_PNG" --out "$ICONSET/$n" >/dev/null
done

# --- 3. Compiler en .icns --------------------------------------------------
mkdir -p "$(dirname "$OUT_ICNS")"
iconutil -c icns "$ICONSET" -o "$OUT_ICNS"

echo "Built: $OUT_ICNS"
ls -la "$OUT_ICNS"
