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
        var inputs: [String] = []
        var it = args.makeIterator()
        while let arg = it.next() {
            switch arg {
            case "--mapping":
                mappingID = it.next()
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
        let engine = ConversionEngine(mapping: mapping)

        print("2FujiRaw CLI — mapping: \(mapping.label)")
        print("→ \(urls.count) fichier(s) à convertir")

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
        Usage : ToFujiRaw --cli [--mapping <id>] <file1> [<file2> ...]

        Options :
          --mapping <id>   ID de mapping (défaut : \(CameraMapping.default.id))
          --help, -h       Affiche cette aide

        Mappings disponibles :
        \(CameraMapping.all.map { "  \($0.id)  —  \($0.label)" }.joined(separator: "\n"))
        """
        print(usage)
    }
}
