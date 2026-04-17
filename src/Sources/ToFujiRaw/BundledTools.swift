import Foundation

enum BundledTools {
    /// URL du binaire dnglab.
    ///
    /// - Si l'app est bundlée : `2FujiRaw.app/Contents/Resources/bin/dnglab`
    /// - Si on tourne en dev (CLI/`swift run`) : fallback sur `vendor/dnglab` à la racine projet
    static var dnglab: URL { resolve(bundleRelative: "bin/dnglab", devRelative: "dnglab") }

    /// URL du binaire exiftool.
    ///
    /// Exiftool est une archive Perl "portable" : le binaire est `exiftool` à la racine,
    /// avec un dossier `lib/` à côté. On pointe vers le script directement.
    static var exiftool: URL { resolve(bundleRelative: "bin/exiftool/exiftool", devRelative: "exiftool/exiftool") }

    static func verifyAll() throws {
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: dnglab.path) else {
            throw ToolError.missing("dnglab", path: dnglab.path)
        }
        guard fm.isExecutableFile(atPath: exiftool.path) else {
            throw ToolError.missing("exiftool", path: exiftool.path)
        }
    }

    /// Cherche le binaire d'abord dans `Bundle.main.resourceURL`, sinon fallback
    /// sur un `vendor/` dérivé du cwd (dev) ou du path de l'exécutable.
    private static func resolve(bundleRelative: String, devRelative: String) -> URL {
        if let res = Bundle.main.resourceURL {
            let bundled = res.appendingPathComponent(bundleRelative)
            if FileManager.default.isExecutableFile(atPath: bundled.path) {
                return bundled
            }
        }
        // Dev fallback : remonter depuis le cwd jusqu'à trouver un dossier vendor/
        for base in devSearchRoots() {
            let candidate = base.appendingPathComponent("vendor").appendingPathComponent(devRelative)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        // Par défaut : retourner le chemin bundle (verifyAll remontera l'erreur proprement)
        return (Bundle.main.resourceURL ?? URL(fileURLWithPath: "/"))
            .appendingPathComponent(bundleRelative)
    }

    private static func devSearchRoots() -> [URL] {
        var roots: [URL] = []
        let fm = FileManager.default
        var cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
        roots.append(cwd)
        // remonter 4 niveaux max
        for _ in 0..<4 {
            cwd = cwd.deletingLastPathComponent()
            roots.append(cwd)
        }
        // Chemin de l'exécutable (`.build/release/ToFujiRaw` → remonter à la racine projet)
        let exePath = URL(fileURLWithPath: CommandLine.arguments[0])
            .resolvingSymlinksInPath()
        var exeBase = exePath.deletingLastPathComponent()
        for _ in 0..<6 {
            roots.append(exeBase)
            exeBase = exeBase.deletingLastPathComponent()
        }
        return roots
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
