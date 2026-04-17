import SwiftUI

/// Palette et primitives visuelles — style néo-rétro lumineux.
///
/// Direction : fond crème chaud, accents magenta + cyan néon, typo monospace.
/// On évite le full-sombre synthwave : on reste "lumineux" (accessible, joyeux)
/// tout en gardant les signes du rétro (pixel-art, scanlines, contours épais).
enum Theme {
    static let cream     = Color(red: 0.98, green: 0.95, blue: 0.88)    // fond principal
    static let peach     = Color(red: 0.99, green: 0.88, blue: 0.78)    // gradient bas
    static let magenta   = Color(red: 0.98, green: 0.24, blue: 0.55)    // accent primaire
    static let cyan      = Color(red: 0.27, green: 0.82, blue: 0.87)    // accent secondaire (drop active)
    static let limeCrt   = Color(red: 0.36, green: 0.86, blue: 0.44)    // progression / succès
    static let ink       = Color(red: 0.15, green: 0.11, blue: 0.28)    // texte principal (violet très foncé, pas noir)
    static let inkSoft   = Color(red: 0.35, green: 0.31, blue: 0.48)    // texte secondaire
    static let error     = Color(red: 0.90, green: 0.22, blue: 0.22)

    static let monoLarge   = Font.system(size: 32, weight: .bold, design: .monospaced)
    static let monoTitle   = Font.system(size: 14, weight: .semibold, design: .monospaced)
    static let monoBody    = Font.system(size: 12, weight: .regular,  design: .monospaced)
    static let monoCaption = Font.system(size: 10, weight: .regular,  design: .monospaced)

    /// Dégradé de fond de la fenêtre.
    static var background: LinearGradient {
        LinearGradient(
            colors: [cream, peach],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

/// Bouton principal, style "cartouche" rétro : fond plein, contour épais,
/// ombre portée nette (pas de blur) pour évoquer l'impression 2D.
struct RetroButtonStyle: ButtonStyle {
    var color: Color = Theme.magenta
    var textColor: Color = .white
    var isEnabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        let effectiveColor = isEnabled ? color : color.opacity(0.35)
        let pressed = configuration.isPressed
        return configuration.label
            .font(Theme.monoTitle)
            .foregroundStyle(textColor)
            .padding(.horizontal, 22)
            .padding(.vertical, 10)
            .background(
                Rectangle()
                    .fill(effectiveColor)
            )
            .overlay(
                Rectangle()
                    .stroke(Theme.ink, lineWidth: 2)
            )
            // Ombre "hard" : un rectangle sombre décalé, classique pixel-art
            .offset(x: pressed ? 2 : 0, y: pressed ? 2 : 0)
            .background(
                Rectangle()
                    .fill(Theme.ink)
                    .offset(x: 4, y: 4)
            )
            .animation(.easeOut(duration: 0.08), value: pressed)
    }
}

/// Chip / tag monospace pour afficher une info compacte (nb fichiers, état…).
struct RetroChip: View {
    let label: String
    var color: Color = Theme.ink

    var body: some View {
        Text(label)
            .font(Theme.monoCaption)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .overlay(
                Rectangle()
                    .stroke(color, lineWidth: 1.5)
            )
    }
}

/// Barre de progression "segmentée" : N cases carrées qui s'allument au fil de
/// la conversion, façon loading bar arcade.
struct SegmentedProgressBar: View {
    let done: Int
    let total: Int
    var segments: Int = 20

    var body: some View {
        let filledCount: Int = {
            guard total > 0 else { return 0 }
            let ratio = Double(done) / Double(total)
            return min(segments, max(0, Int((ratio * Double(segments)).rounded(.down))))
        }()

        HStack(spacing: 3) {
            ForEach(0..<segments, id: \.self) { i in
                Rectangle()
                    .fill(i < filledCount ? Theme.limeCrt : Color.clear)
                    .overlay(Rectangle().stroke(Theme.ink, lineWidth: 1))
                    .frame(height: 16)
            }
        }
    }
}
