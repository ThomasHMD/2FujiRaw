# 2FujiRaw — spec du projet

App macOS standalone (`.dmg`) qui convertit des RAW non-Fuji en DNG "maquillés" en Fuji, pour débloquer les **Film Simulations Fuji natives** (Provia, Velvia, Astia, Classic Chrome, Classic Neg, Eterna, Acros, Pro Neg Hi/Std, Nostalgic Neg, Monochrome, Sepia) dans Lightroom Classic sur des fichiers d'autres boîtiers.

V1 : **Hasselblad X2D II 100C → Fuji GFX 100S II**. Architecture prévue pour ajouter d'autres couples (Ricoh → Fuji, Leica → Fuji, etc.).

**Contrainte forte : `.app` standalone totalement autonome, zéro dépendance externe à installer côté utilisateur.** Tous les outils (dnglab, exiftool) sont bundlés dans le `.app`. Taille cible : **< 30 Mo**.

---

## Pourquoi cette approche

### Le vrai mécanisme du lock Lightroom

Les Film Simulations Fuji **ne sont pas des fichiers `.dcp` sur disque**. Elles sont hardcodées dans le binaire du plugin Camera Raw d'Adobe et appliquées automatiquement quand LrC détecte un fichier venant d'un boîtier Fuji.

Le filtre est sur **le `Model` / `UniqueCameraModel` du RAW**, pas sur un fichier profil. Donc le hack ne consiste pas à modifier un profil, mais à faire passer le RAW pour un fichier Fuji.

### Pourquoi passer par le DNG

On ne peut pas simplement modifier les tags EXIF d'un `.3FR` Hasselblad : LrC reconnaît le format binaire propriétaire et utilise son parser Hasselblad dédié, indépendamment de ce que disent les tags.

En convertissant en **DNG** (format TIFF standard universel), LrC perd le lien avec le format propriétaire d'origine et se base uniquement sur les tags TIFF standards (`Make`, `Model`, `UniqueCameraModel`). Là on peut spoofer librement.

### Pourquoi spoofer en GFX 100S II (et pas X-T5)

| Boîtier | Capteur | Démosaïque | Résolution | Format |
|---|---|---|---|---|
| Hasselblad X2D II 100C | Sony IMX461 | Bayer | 100 Mpx | 4:3 MF |
| Fuji GFX 100S II | Sony IMX461 | Bayer | 102 Mpx | 4:3 MF |
| Fuji X-T5 | X-Trans | **X-Trans** (≠ Bayer) | 40 Mpx | 3:2 APS-C |

Le GFX 100S II et le X2D II partagent **le même capteur physique** (Sony IMX461). Le spoof est techniquement transparent pour le moteur de démosaïque de Camera Raw.

À l'inverse, spoofer en X-T5 forcerait ACR à tenter une démosaïque X-Trans sur des données Bayer = artefacts garantis.

---

## Stack technique — tout bundlé

| Composant | Rôle | Taille | Source |
|---|---|---|---|
| Binaire SwiftUI | UI + orchestration | ~5 Mo | compilé depuis `src/` |
| **dnglab (patché)** | conversion RAW → DNG | ~12 Mo | compilé depuis sources via `scripts/build-dnglab.sh` (alias X2D II 100C ajouté, upstream 0.7.2 ne le supporte pas encore) |
| **exiftool** (portable) | réécriture tags TIFF du DNG | ~10-15 Mo | https://exiftool.org/ (archive `.tar.gz` macOS) |
| **Total `.app`** | | **~25-30 Mo** | |

> ⚠️ dnglab 0.7.2 **officiel** ne supporte que le Hasselblad X2D 100C (modèle 2022), pas le X2D II 100C (2024). Les deux boîtiers partagent le même capteur IMX461 → on ajoute simplement les alias `Hasselblad X2D II 100C` et `X2D II 100C` dans `rawler/data/cameras/hasselblad/x2d_100c.toml`, puis on recompile. Voir `scripts/build-dnglab.sh` (idempotent, relançable).

Les binaires `dnglab` et `exiftool` sont placés dans `2FujiRaw.app/Contents/Resources/bin/` et invoqués via `Process` en Swift. L'utilisateur n'installe rien d'autre que le `.dmg`.

### Alternative envisagée pour l'étape 2 (plus léger encore)

Une fois dnglab utilisé pour la conversion RAW→DNG, la réécriture des tags TIFF du DNG peut se faire **en Swift natif via ImageIO** (`CGImageSourceCopyProperties` / `CGImageDestinationAddImageAndMetadata`) — éliminerait le besoin de bundler exiftool (~-10 Mo).

Contrainte : ImageIO sait lire/écrire les tags TIFF standards mais peut être capricieux avec les DNG contenant des sous-IFDs. **À tester au moment du dev.** Fallback = exiftool bundlé.

Deuxième piste : **dnglab peut peut-être passer directement les tags Make/Model à la conversion** (`--exif` ou option équivalente). Si oui, tout se fait en une passe, aucun besoin d'exiftool. **À vérifier dans la doc dnglab au moment du dev.**

---

## Chaîne technique

```
.3FR Hasselblad
      │
      ▼  [étape 1] dnglab convert
.dng (tags: Make="Hasselblad", Model="X2D II 100C")
      │
      ▼  [étape 2] exiftool (ou ImageIO natif, ou dnglab --exif)
.dng (tags: Make="FUJIFILM", Model="GFX 100S II", UniqueCameraModel="Fujifilm GFX 100S II")
      │
      ▼  [étape 3] import dans LrC
Profils Fuji natifs disponibles (Provia, Velvia, Classic Chrome, Classic Neg, Acros, Eterna, etc.)
```

### Commandes équivalentes manuelles (pour test)

```bash
# 1. Conversion DNG avec dnglab
./vendor/dnglab convert --compression lossless INPUT.3FR OUTPUT.dng

# 2. Spoof des tags
./vendor/exiftool \
    -Make="FUJIFILM" \
    -Model="GFX 100S II" \
    -UniqueCameraModel="Fujifilm GFX 100S II" \
    -overwrite_original \
    OUTPUT.dng
```

---

## Prérequis côté dev (machine Thomas)

| Outil | État | Action |
|---|---|---|
| Swift CLI 6.3.1+ | ✅ installé (Command Line Tools) | — |
| exiftool système | ✅ `/opt/homebrew/bin/exiftool` | (pour tests manuels, pas bundlé directement) |
| create-dmg | ⚠️ à installer | `brew install create-dmg` |
| Xcode.app | ❌ non installé (pas nécessaire) | on build sans Xcode via SwiftPM + bundling manuel |

**Aucun prérequis côté utilisateur final** : il double-clique le `.dmg`, glisse `2FujiRaw.app` dans Applications, c'est fini.

---

## Architecture du projet

```
2FujiRaw/
├── Projet.md                          # ce fichier
├── .gitignore
├── src/
│   ├── Package.swift                  # manifeste SwiftPM (target executable)
│   └── Sources/
│       └── ToFujiRaw/                 # nom module Swift (ne peut pas commencer par chiffre)
│           ├── ToFujiRawApp.swift     # @main entry
│           ├── ContentView.swift      # fenêtre principale
│           ├── DropZoneView.swift     # composant drag&drop
│           ├── CameraMapping.swift    # enum extensible des couples source→cible
│           ├── ConversionEngine.swift # orchestration dnglab + exiftool│           ├── BundledTools.swift     # résolution chemins binaires bundlés
│           └── Resources/
│               └── AppIcon.icns       # à générer (iconutil)
├── vendor/                            # binaires externes (gitignored, fetched via script)
│   ├── dnglab                         # binaire dnglab macOS arm64
│   └── exiftool/                      # archive portable exiftool
├── scripts/
│   ├── fetch-deps.sh                  # télécharge dnglab + exiftool dans vendor/
│   ├── build.sh                       # compile + assemble .app + bundle vendor + codesign
│   └── make-dmg.sh                    # génère le .dmg final
└── dist/                              # output de build (gitignored)
    ├── 2FujiRaw.app
    └── 2FujiRaw.dmg
```

---

## Spec UI / UX

### Fenêtre unique, 500×400, non redimensionnable

```
┌────────────────────────────────────────────────┐
│                                                │
│                  2FujiRaw                      │
│     Hasselblad → Fuji look for Lightroom       │
│                                                │
│  ┌──────────────────────────────────────────┐  │
│  │                                          │  │
│  │      Glissez vos RAW ici                 │  │
│  │             ou                           │  │
│  │       [+ Ajouter des fichiers]           │  │
│  │                                          │  │
│  │       (0 fichiers prêts)                 │  │
│  │                                          │  │
│  └──────────────────────────────────────────┘  │
│                                                │
│  Mapping :                                     │
│  [ Hasselblad X2D II → Fuji GFX 100S II  ▾ ]   │
│                                                │
│                 [ Convertir ]                  │
│                                                │
└────────────────────────────────────────────────┘
```

### États

1. **Vide** : drop zone + bouton "+ Ajouter". Bouton "Convertir" grisé.
2. **Fichiers ajoutés** : liste scrollable avec nom + bouton `×` par fichier. Compteur "N fichiers prêts".
3. **Conversion en cours** : barre de progression + libellé "X/N". Bouton "Annuler".
4. **Terminé** : "N fichiers convertis dans `<dossier>/DNG-Fuji-Converted/`". Bouton "Ouvrir le dossier" + "Recommencer".
5. **Erreur** : message clair. Si un outil bundlé manque, c'est un bug de packaging (à investiguer, pas à demander à l'utilisateur).

### Comportement de sortie

Pour chaque fichier source, DNG créé dans **un sous-dossier `DNG-Fuji-Converted/` au même niveau que le fichier source**.

Exemple : drop de `/Users/x/Shoots/2026-04/B0000246.3FR` → `/Users/x/Shoots/2026-04/DNG-Fuji-Converted/B0000246.dng`.

Si plusieurs fichiers viennent de dossiers différents, chaque dossier source reçoit son propre `DNG-Fuji-Converted/`.

Si un fichier sortie existe déjà : option utilisateur **skip / écraser / suffixer** (preference par défaut : suffixer `_spoofed.dng`).

### Formats acceptés en entrée

V1 : `.3FR`, `.FFF` (Hasselblad).
Prévoir extension facile via `CameraMapping.sourceExtensions`.

---

## Spec logique métier

### `CameraMapping.swift`

```swift
import Foundation

struct CameraMapping: Identifiable, Hashable {
    let id: String
    let label: String
    let sourceExtensions: [String]      // ex ["3FR", "FFF"]
    let targetMake: String
    let targetModel: String
    let targetUniqueCameraModel: String

    static let all: [CameraMapping] = [
        CameraMapping(
            id: "hassy-x2d2-to-fuji-gfx100s2",
            label: "Hasselblad X2D II → Fuji GFX 100S II",
            sourceExtensions: ["3FR", "FFF"],
            targetMake: "FUJIFILM",
            targetModel: "GFX 100S II",
            targetUniqueCameraModel: "Fujifilm GFX 100S II"
        ),
        // Futurs mappings :
        // .init(id: "ricoh-griii-to-fuji-xh2s", label: "Ricoh GR III → Fuji X-H2S", ...)
        // .init(id: "leica-q3-to-fuji-gfx100ii", label: "Leica Q3 → Fuji GFX 100 II", ...)
    ]

    static var `default`: CameraMapping { all[0] }
}
```

### `BundledTools.swift`

```swift
import Foundation

enum BundledTools {
    /// URL du binaire dnglab bundlé dans Contents/Resources/bin/
    static var dnglab: URL {
        Bundle.main.resourceURL!
            .appendingPathComponent("bin/dnglab")
    }

    /// URL du binaire exiftool bundlé dans Contents/Resources/bin/exiftool/exiftool
    static var exiftool: URL {
        Bundle.main.resourceURL!
            .appendingPathComponent("bin/exiftool/exiftool")
    }

    static func verifyAll() throws {
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: dnglab.path) else {
            throw ToolError.missing("dnglab", path: dnglab.path)
        }
        guard fm.isExecutableFile(atPath: exiftool.path) else {
            throw ToolError.missing("exiftool", path: exiftool.path)
        }
    }
}

enum ToolError: LocalizedError {
    case missing(String, path: String)

    var errorDescription: String? {
        switch self {
        case .missing(let name, let path):
            return "Outil interne manquant : \(name) (attendu à \(path)). Bug de packaging."
        }
    }
}
```

### `ConversionEngine.swift`

```swift
import Foundation

struct ConversionProgress {
    let processed: Int
    let total: Int
    let lastOutput: URL?
}

enum ConversionError: LocalizedError {
    case tools(ToolError)
    case dngConvertFailed(source: URL, stderr: String)
    case spoofFailed(dng: URL, stderr: String)

    var errorDescription: String? { /* TODO */ nil }
}

struct ConversionEngine {
    let mapping: CameraMapping
    enum OverwriteStrategy { case skip, overwrite, suffix }
    var overwriteStrategy: OverwriteStrategy = .suffix

    /// Convertit un RAW source en DNG spoofé.
    /// - Sortie: <parent_source>/DNG-Fuji-Converted/<nom>.dng
    func convert(_ source: URL) async throws -> URL {
        // 1. Resolve output dir + filename (gérer collision selon overwriteStrategy)
        // 2. Run dnglab : process exec, capture stderr, throw si code != 0
        // 3. Run exiftool : process exec avec -Make/-Model/-UniqueCameraModel, overwrite_original
        // 4. Return URL du DNG final
        fatalError("TODO")
    }

    /// Traite un batch en série, publie progress via AsyncStream.
    func convertBatch(_ sources: [URL]) -> AsyncThrowingStream<ConversionProgress, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try BundledTools.verifyAll()
                    for (i, src) in sources.enumerated() {
                        let out = try await convert(src)
                        continuation.yield(ConversionProgress(
                            processed: i + 1,
                            total: sources.count,
                            lastOutput: out
                        ))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // Helper générique pour exécuter un binaire avec arguments et capturer stdout/stderr
    private func run(_ binary: URL, args: [String]) throws -> (stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = binary
        process.arguments = args
        let outPipe = Pipe(), errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()
        let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            // à gérer dans la méthode appelante
        }
        return (out, err)
    }
}
```

### `ContentView.swift` (squelette minimal)

```swift
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var files: [URL] = []
    @State private var mapping: CameraMapping = .default
    @State private var isConverting = false
    @State private var progress: (done: Int, total: Int) = (0, 0)
    @State private var errorMessage: String?
    @State private var lastOutputDir: URL?

    var body: some View {
        VStack(spacing: 16) {
            Text("2FujiRaw").font(.largeTitle).bold()
            Text("Hasselblad → Fuji look for Lightroom")
                .foregroundStyle(.secondary)
                .font(.subheadline)

            DropZoneView(files: $files, mapping: mapping)
                .frame(maxHeight: 180)

            Picker("Mapping", selection: $mapping) {
                ForEach(CameraMapping.all) { m in
                    Text(m.label).tag(m)
                }
            }
            .pickerStyle(.menu)
            .disabled(isConverting)

            if isConverting {
                ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                Text("\(progress.done) / \(progress.total)")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else {
                Button("Convertir") {
                    Task { await runConversion() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(files.isEmpty)
            }

            if let dir = lastOutputDir, !isConverting {
                Button("Ouvrir le dossier") {
                    NSWorkspace.shared.activateFileViewerSelecting([dir])
                }
                .buttonStyle(.bordered)
            }

            if let err = errorMessage {
                Text(err).foregroundStyle(.red).font(.caption)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
        .frame(width: 500, height: 400)
    }

    func runConversion() async {
        errorMessage = nil
        isConverting = true
        progress = (0, files.count)

        let engine = ConversionEngine(mapping: mapping)
        do {
            for try await p in engine.convertBatch(files) {
                progress = (p.processed, p.total)
                if let out = p.lastOutput { lastOutputDir = out.deletingLastPathComponent() }
            }
            files = [] // reset liste après succès
        } catch {
            errorMessage = error.localizedDescription
        }
        isConverting = false
    }
}
```

### `DropZoneView.swift` (squelette)

```swift
import SwiftUI
import UniformTypeIdentifiers

struct DropZoneView: View {
    @Binding var files: [URL]
    let mapping: CameraMapping
    @State private var isTargeted = false

    private var allowedTypes: [UTType] {
        // On accepte tous les types de fichiers, on filtre par extension dans onDrop
        [.fileURL]
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary,
                    style: StrokeStyle(lineWidth: 2, dash: [6])
                )
                .background(RoundedRectangle(cornerRadius: 12).fill(.quaternary.opacity(0.3)))

            VStack(spacing: 8) {
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                if files.isEmpty {
                    Text("Glissez vos RAW ici").font(.headline)
                    Button("+ Ajouter des fichiers") { openPanel() }
                        .buttonStyle(.bordered)
                } else {
                    Text("\(files.count) fichier\(files.count > 1 ? "s" : "") prêt\(files.count > 1 ? "s" : "")")
                        .font(.headline)
                    Button("Vider la liste") { files.removeAll() }
                        .buttonStyle(.bordered)
                }
            }
            .padding()
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            Task { await handleDrop(providers) }
            return true
        }
    }

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.item]  // filtrage ensuite par extension
        if panel.runModal() == .OK {
            addFiles(panel.urls)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) async {
        var urls: [URL] = []
        for provider in providers {
            if let url = try? await provider.loadFileURL() {
                urls.append(url)
            }
        }
        await MainActor.run { addFiles(urls) }
    }

    private func addFiles(_ urls: [URL]) {
        let allowed = Set(mapping.sourceExtensions.map { $0.lowercased() })
        let filtered = urls.filter { allowed.contains($0.pathExtension.lowercased()) }
        files.append(contentsOf: filtered)
        // dedupe
        var seen = Set<URL>()
        files = files.filter { seen.insert($0).inserted }
    }
}

// Extension utilitaire pour NSItemProvider
private extension NSItemProvider {
    func loadFileURL() async throws -> URL? {
        try await withCheckedThrowingContinuation { cont in
            _ = self.loadObject(ofClass: URL.self) { url, error in
                if let error = error { cont.resume(throwing: error) }
                else { cont.resume(returning: url) }
            }
        }
    }
}
```

### `ToFujiRawApp.swift`

```swift
import SwiftUI

@main
struct ToFujiRawApp: App {
    var body: some Scene {
        Window("2FujiRaw", id: "main") {
            ContentView()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 500, height: 400)
    }
}
```

---

## `Package.swift`

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ToFujiRaw",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ToFujiRaw",
            path: "Sources/ToFujiRaw",
            exclude: ["Resources"]   // Resources gérées au bundling, pas SwiftPM
        )
    ]
)
```

---

## Scripts de build

### `scripts/fetch-deps.sh`

Télécharge dnglab + exiftool dans `vendor/`. À relancer seulement si on veut bump les versions.

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/vendor"
mkdir -p "$VENDOR"

# -- dnglab (arm64) --
DNGLAB_VERSION="0.7.0"   # à bumper si une release plus récente existe
DNGLAB_URL="https://github.com/dnglab/dnglab/releases/download/v${DNGLAB_VERSION}/dnglab-macos-arm64-${DNGLAB_VERSION}.tar.gz"
echo "Fetching dnglab ${DNGLAB_VERSION}..."
curl -L "$DNGLAB_URL" -o /tmp/dnglab.tar.gz
tar -xzf /tmp/dnglab.tar.gz -C /tmp
# Adapter le chemin selon la structure réelle de l'archive
cp /tmp/dnglab "$VENDOR/dnglab"
chmod +x "$VENDOR/dnglab"

# -- exiftool (portable) --
EXIF_VERSION="13.55"
EXIF_URL="https://exiftool.org/Image-ExifTool-${EXIF_VERSION}.tar.gz"
echo "Fetching exiftool ${EXIF_VERSION}..."
curl -L "$EXIF_URL" -o /tmp/exiftool.tar.gz
rm -rf "$VENDOR/exiftool"
mkdir -p "$VENDOR/exiftool"
tar -xzf /tmp/exiftool.tar.gz -C "$VENDOR/exiftool" --strip-components=1

echo "Vendor ready:"
ls -la "$VENDOR"
```

### `scripts/build.sh`

```bash
#!/usr/bin/env bash
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

cp "$ROOT/src/.build/release/ToFujiRaw" "$APP/Contents/MacOS/2FujiRaw"
cp "$ROOT/vendor/dnglab" "$APP/Contents/Resources/bin/dnglab"
cp -R "$ROOT/vendor/exiftool" "$APP/Contents/Resources/bin/exiftool"

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
```

### `scripts/make-dmg.sh`

```bash
#!/usr/bin/env bash
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
```

---

## Roadmap d'implémentation

### Étape 1 — Valider la chaîne technique sur 1 fichier (manuel, pas d'app)
- [x] `scripts/fetch-deps.sh` : dnglab 0.7.2 + exiftool 13.56 récupérés dans `vendor/`
- [x] Chaîne validée manuellement par Thomas (DNG spoofé reconnu par LrC, Film Simulations Fuji accessibles)
- [x] **dnglab 0.7.2 ne permet pas d'injecter Make/Model à la conversion** (vérifié via `dnglab convert --help`) → 2 passes obligatoires : `dnglab convert` puis `exiftool`
- [x] Flags dnglab retenus : `--compression lossless` (défaut), `--embed-raw true` (défaut), `--dng-preview true` (défaut). Pas besoin de toucher aux autres
- [ ] `brew install create-dmg` (pour étape 4)

### Étape 2 — Logique métier en Swift CLI (sans GUI)
- [x] `BundledTools.swift` : résolveur bundle/dev avec fallback `vendor/` en dev
- [x] `ConversionEngine.swift` : `convert()` implémenté (dnglab → exiftool, gestion collision par suffixe)
- [x] `CameraMapping.swift` : mapping X2D II → GFX 100S II
- [x] Entry point CLI (`--cli`) dans `ToFujiRawApp.swift` (via `Entry` struct `@main`)
- [x] `CLI.swift` : parse args, lance `convertBatch`, imprime progress
- [x] Testé sur 1 fichier `.3FR` (B0000132, 211 Mo → DNG 303 Mo, tags FUJIFILM OK)
- [ ] Test visuel dans LrC : Film Simulations Fuji disponibles dans le panneau Profil
- [ ] Tester sur 5 fichiers de types variés

### Étape 3 — GUI SwiftUI
- [x] `ContentView`, `DropZoneView` (style néo-rétro lumineux : monospace, palette crème/magenta/cyan, ombres dures pixel-art)
- [x] `Theme.swift` : palette + `RetroButtonStyle` + `SegmentedProgressBar` + `RetroChip`
- [x] Progress bar segmentée (20 cases qui s'allument en vert-CRT)
- [x] Gestion erreurs (bannière `ERR` rouge) et état "Terminé" (bouton OPEN OUTPUT)
- [x] Bouton "OPEN OUTPUT" via `NSWorkspace.activateFileViewerSelecting`
- [x] Hiérarchie visuelle : CONVERT seul élément magenta plein, mapping dropdown neutre subordonné

### Étape 4 — Packaging
- [x] `scripts/build.sh` : compile Swift release arm64, assemble `.app`, bundle `dnglab` + `exiftool`, Info.plist, codesign ad-hoc
- [x] Icône `AppIcon.icns` — généré via `scripts/make-icon.sh` (Swift + CoreGraphics + sips + iconutil). Style squircle crème-pêche, "2FR" magenta monospace, "→ FUJI" cyan, ombre magenta pixel-art.
- [x] `scripts/make-dmg.sh` — utilise `hdiutil` (builtin macOS) plutôt que `create-dmg` (timeouts AppleScript) pour zéro dépendance
- [x] Premier `.dmg` (`dist/2FujiRaw.dmg`, ~19 Mo compressé, `.app` 46 Mo décompressé)

### Étape 5 (optionnelle) — Extensions
- [ ] Ajouter les mappings Ricoh, Leica, etc. dans `CameraMapping.all`
- [ ] Support drop de dossiers entiers (récursion sur extensions)
- [ ] Option "ouvrir directement dans LrC après conversion" (`open -a "Adobe Lightroom Classic" file.dng`)
- [ ] Drag-sortie depuis la fenêtre : pouvoir dragger les DNG générés depuis l'app vers Finder

---

## Points ouverts à trancher au moment de coder

1. **Flags dnglab exacts** : à valider via `dnglab convert --help` après `fetch-deps.sh`. Points à vérifier : niveau de compression, preservation metadata originale, option pour injecter des tags à la conversion.
2. **exiftool vs ImageIO natif vs dnglab direct** : choisir en étape 1 selon ce que dnglab permet. Ordre de préférence : (a) dnglab injecte tout → plus d'exiftool à bundler, (b) ImageIO Swift, (c) exiftool bundlé.
3. **Gestion collision fichier de sortie** : par défaut suffixer `_spoofed.dng`. Préférence peut devenir une option utilisateur (menu "Fichier" ou popup).
4. **Log file** : créer `~/Library/Logs/2FujiRaw/conversion.log` pour debug. Utile quand l'app est en prod.
5. **Signature** : ad-hoc suffit pour usage perso. Si distribution à d'autres photographes un jour → Developer ID Apple (99 $/an).

---

## Références

- Méthode originale (DNG spoof) : https://rbrant.substack.com/p/how-to-use-fujifilm-profiles-with
- dnglab : https://github.com/dnglab/dnglab
- exiftool : https://exiftool.org/
- SwiftPM doc : https://www.swift.org/package-manager/
- create-dmg : https://github.com/create-dmg/create-dmg
