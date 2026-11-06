import Foundation

/// Entry point CLI, utilisé par `swift run ToFujiRaw --cli ...` pour tester la
/// logique métier sans passer par la GUI SwiftUI.
///
/// Usage :
///     ToFujiRaw --cli [--mapping <id>] <file1.3fr> [<file2.3fr> ...]
enum CLI {
    static func run() -> Never {
        var args = Array(CommandLine.arguments.dropFirst())
        args.removeAll { $0 == "--cli" }

        var mappingID: String? = nil
        var donorPath: String? = nil
        var preserveOriginalLeicaBodyInfo = false
        var inputs: [String] = []
        var it = args.makeIterator()
        while let arg = it.next() {
            switch arg {
            case "--mapping":
                mappingID = it.next()
            case "--donor":
                donorPath = it.next()
            case "--preserve-leica-body-info":
                preserveOriginalLeicaBodyInfo = true
            case "--help", "-h":
                printUsage()
                exit(0)
            default:
                inputs.append(arg)
            }
        }

        guard !inputs.isEmpty else {
            printUsage()
            exit(2)
        }

        let mapping: CameraMapping
        if let id = mappingID, let m = CameraMapping.all.first(where: { $0.id == id }) {
            mapping = m
        } else {
            mapping = .default
        }

        let urls = inputs.map { URL(fileURLWithPath: $0) }
        let donorURL = donorPath.map { URL(fileURLWithPath: $0) }
        let engine = ConversionEngine(
            mapping: mapping,
            donorURL: donorURL,
            options: ConversionOptions(
                preserveOriginalLeicaBodyInfo: preserveOriginalLeicaBodyInfo
            )
        )

        print("2FujiRaw CLI — mapping: \(mapping.label)")
        print("→ \(urls.count) fichier(s) à convertir")
        if let donorURL {
            print("→ donor: \(donorURL.path)")
        }

        let sem = DispatchSemaphore(value: 0)
        var exitCode: Int32 = 0
        Task {
            do {
                for try await progress in engine.convertBatch(urls) {
                    if let out = progress.lastOutput {
                        print("[\(progress.processed)/\(progress.total)] ✓ \(out.path)")
                    }
                }
                print("OK")
            } catch {
                FileHandle.standardError.write(Data("Erreur : \(error.localizedDescription)\n".utf8))
                exitCode = 1
            }
            sem.signal()
        }
        sem.wait()
        exit(exitCode)
    }

    private static func printUsage() {
        let usage = """
        Usage : ToFujiRaw --cli [--mapping <id>] [--donor <file.3fr>] <file1> [<file2> ...]

        Options :
          --mapping <id>   ID de mapping (défaut : \(CameraMapping.default.id))
          --donor <file>   Override le template X2D bundlé pour les mappings Leica
          --preserve-leica-body-info
                            Remplace uniquement la chaîne Model par le modèle Leica source
          --help, -h       Affiche cette aide

        Mappings disponibles :
        \(CameraMapping.all.map { "  \($0.id)  —  \($0.label)" }.joined(separator: "\n"))
        """
        print(usage)
    }
}
