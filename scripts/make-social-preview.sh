#!/usr/bin/env bash
# Génère la "social preview image" 1280×640 du repo GitHub — c'est ce qui
# apparaît dans les cartes Open Graph quand on partage le lien sur les
# réseaux sociaux.
#
# Format recommandé par GitHub : 1280×640 (ratio 2:1), au moins 640×320.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/assets/social-preview.png"
mkdir -p "$(dirname "$OUT")"

SWIFT_SCRIPT="$(mktemp -t 2fujiraw-social-XXXXXX).swift"
cat > "$SWIFT_SCRIPT" <<'SWIFT'
import AppKit
import CoreGraphics
import Foundation

let width: CGFloat = 1280
let height: CGFloat = 640
let image = NSImage(size: NSSize(width: width, height: height))
image.lockFocus()

let cream   = NSColor(calibratedRed: 0.98, green: 0.95, blue: 0.88, alpha: 1)
let peach   = NSColor(calibratedRed: 0.99, green: 0.88, blue: 0.78, alpha: 1)
let magenta = NSColor(calibratedRed: 0.98, green: 0.24, blue: 0.55, alpha: 1)
let cyan    = NSColor(calibratedRed: 0.27, green: 0.82, blue: 0.87, alpha: 1)
let ink     = NSColor(calibratedRed: 0.15, green: 0.11, blue: 0.28, alpha: 1)
let inkSoft = NSColor(calibratedRed: 0.35, green: 0.31, blue: 0.48, alpha: 1)

// Fond : gradient vertical crème → pêche
let gradient = NSGradient(colors: [cream, peach])!
gradient.draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: 270)

// Scanlines décoratives cyan en haut et en bas (style rétro)
cyan.withAlphaComponent(0.5).setFill()
NSBezierPath(rect: NSRect(x: 80, y: height - 70, width: width - 160, height: 4)).fill()
NSBezierPath(rect: NSRect(x: 80, y: 70, width: width - 160, height: 4)).fill()

// Carton "cartouche" central : ombre magenta pixel-art
let cardRect = NSRect(x: 110, y: 170, width: width - 220, height: 300)
let shadowRect = cardRect.offsetBy(dx: 16, dy: -16)
magenta.setFill()
NSBezierPath(rect: shadowRect).fill()
NSColor.white.setFill()
NSBezierPath(rect: cardRect).fill()
ink.setStroke()
let cardPath = NSBezierPath(rect: cardRect)
cardPath.lineWidth = 6
cardPath.stroke()

// Titre "2FUJIRAW" — gros, magenta, monospace bold
let title = "2FUJIRAW"
let titleFont = NSFont.monospacedSystemFont(ofSize: 140, weight: .bold)
let titleAttrs: [NSAttributedString.Key: Any] = [
    .font: titleFont,
    .foregroundColor: magenta,
    .kern: 2,
]
let titleStr = NSAttributedString(string: title, attributes: titleAttrs)
let titleSize = titleStr.size()
let titleRect = NSRect(
    x: (width - titleSize.width) / 2,
    y: cardRect.midY - 10,
    width: titleSize.width,
    height: titleSize.height
)
titleStr.draw(in: titleRect)

// Sous-titre en ink soft, monospace, petit
let subtitle = "HASSELBLAD → FUJI LOOK  //  LIGHTROOM PROFILES"
let subFont = NSFont.monospacedSystemFont(ofSize: 28, weight: .semibold)
let subAttrs: [NSAttributedString.Key: Any] = [
    .font: subFont,
    .foregroundColor: ink,
    .kern: 3,
]
let subStr = NSAttributedString(string: subtitle, attributes: subAttrs)
let subSize = subStr.size()
let subRect = NSRect(
    x: (width - subSize.width) / 2,
    y: cardRect.minY + 50,
    width: subSize.width,
    height: subSize.height
)
subStr.draw(in: subRect)

// Badge version en bas à gauche
let badge = "  v0.1.0  "
let badgeFont = NSFont.monospacedSystemFont(ofSize: 22, weight: .bold)
let badgeAttrs: [NSAttributedString.Key: Any] = [
    .font: badgeFont,
    .foregroundColor: ink,
]
let badgeStr = NSAttributedString(string: badge, attributes: badgeAttrs)
let badgeSize = badgeStr.size()
let badgeRect = NSRect(x: 110, y: 105, width: badgeSize.width, height: badgeSize.height)
NSBezierPath(rect: badgeRect.insetBy(dx: -4, dy: -6)).addClip()
ink.setStroke()
let badgePath = NSBezierPath(rect: badgeRect.insetBy(dx: -4, dy: -6))
badgePath.lineWidth = 2
badgePath.stroke()
badgeStr.draw(in: badgeRect)

// Signature discrète en bas à droite
let sig = "by Thomas Hammoudi"
let sigFont = NSFont.monospacedSystemFont(ofSize: 22, weight: .regular)
let sigAttrs: [NSAttributedString.Key: Any] = [
    .font: sigFont,
    .foregroundColor: inkSoft,
]
let sigStr = NSAttributedString(string: sig, attributes: sigAttrs)
let sigSize = sigStr.size()
sigStr.draw(at: NSPoint(x: width - sigSize.width - 110, y: 105))

image.unlockFocus()

let tiff = image.tiffRepresentation!
let bitmap = NSBitmapImageRep(data: tiff)!
let png = bitmap.representation(using: .png, properties: [:])!
let outPath = CommandLine.arguments[1]
try png.write(to: URL(fileURLWithPath: outPath))
SWIFT

swift "$SWIFT_SCRIPT" "$OUT"
rm -f "$SWIFT_SCRIPT"

SIZE="$(du -h "$OUT" | awk '{print $1}')"
DIMS="$(sips -g pixelWidth -g pixelHeight "$OUT" | awk '/pixelWidth|pixelHeight/ {print $2}' | paste -sd'×' -)"
echo "Built: $OUT  ($DIMS, $SIZE)"
