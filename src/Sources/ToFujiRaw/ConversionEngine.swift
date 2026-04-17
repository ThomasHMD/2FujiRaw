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
    case outputDirectory(URL, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .tools(let e):
            return e.errorDescription
        case .dngConvertFailed(let src, let stderr):
            return "Échec conversion DNG pour \(src.lastPathComponent) : \(stderr)"
        case .spoofFailed(let dng, let stderr):
            return "Échec réécriture des tags pour \(dng.lastPathComponent) : \(stderr)"
        case .outputDirectory(let url, let underlying):
            return "Impossible de créer le dossier de sortie \(url.path) : \(underlying.localizedDescription)"
        }
    }
}

struct ConversionEngine {
    let mapping: CameraMapping
    enum OverwriteStrategy { case skip, overwrite, suffix }
    var overwriteStrategy: OverwriteStrategy = .suffix

    /// Convertit un RAW source en DNG spoofé.
    /// - Sortie: <parent_source>/DNG-Fuji-Converted/<nom>.dng
    func convert(_ source: URL) async throws -> URL {
        let outputDir = source.deletingLastPathComponent()
            .appendingPathComponent("DNG-Fuji-Converted", isDirectory: true)

        do {
            try FileManager.default.createDirectory(
                at: outputDir, withIntermediateDirectories: true)
        } catch {
            throw ConversionError.outputDirectory(outputDir, underlying: error)
        }

        let baseName = source.deletingPathExtension().lastPathComponent
        var outputFile = outputDir.appendingPathComponent("\(baseName).dng")

        if FileManager.default.fileExists(atPath: outputFile.path) {
            switch overwriteStrategy {
            case .skip:
                return outputFile
            case .overwrite:
                try? FileManager.default.removeItem(at: outputFile)
            case .suffix:
                var i = 1
                repeat {
                    outputFile = outputDir.appendingPathComponent("\(baseName)_spoofed\(i == 1 ? "" : "-\(i)").dng")
                    i += 1
                } while FileManager.default.fileExists(atPath: outputFile.path)
            }
        }

        // 1. dnglab convert
        let dngArgs = [
            "convert",
            "--compression", "lossless",
            source.path,
            outputFile.path,
        ]
        let dng = try run(BundledTools.dnglab, args: dngArgs)
        if dng.exitCode != 0 {
            throw ConversionError.dngConvertFailed(
                source: source,
                stderr: dng.stderr.isEmpty ? dng.stdout : dng.stderr)
        }

        // 2. exiftool :
        //    - Spoof Make / Model / UniqueCameraModel pour faire passer le DNG
        //      pour un Fuji aux yeux de LrC
        //    - Marquer le preview comme "valide" via les tags DNG 1.4 :
        //      sans PreviewApplicationName/Version/DateTime, LrC tente de
        //      régénérer le preview à chaque import et reste bloqué sur
        //      un carré gris. Avec ces tags, il accepte le preview bundlé
        //      par dnglab.
        let exifArgs = [
            "-Make=\(mapping.targetMake)",
            "-Model=\(mapping.targetModel)",
            "-UniqueCameraModel=\(mapping.targetUniqueCameraModel)",
            "-PreviewApplicationName=2FujiRaw",
            "-PreviewApplicationVersion=0.1.0",
            "-PreviewDateTime=now",
            "-PreviewColorSpace=sRGB",
            "-overwrite_original",
            outputFile.path,
        ]
        let exif = try run(BundledTools.exiftool, args: exifArgs)
        if exif.exitCode != 0 {
            throw ConversionError.spoofFailed(
                dng: outputFile,
                stderr: exif.stderr.isEmpty ? exif.stdout : exif.stderr)
        }

        return outputFile
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

    private func run(_ binary: URL, args: [String]) throws -> (stdout: String, stderr: String, exitCode: Int32) {
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
        return (out, err, process.terminationStatus)
    }
}
