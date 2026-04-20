import Foundation

struct ConversionProgress {
    let processed: Int
    let total: Int
    let currentPhase: String?
    let currentFileFraction: Double
    let lastOutput: URL?

    var overallFraction: Double {
        guard total > 0 else { return 0 }
        return min(1, (Double(processed) + currentFileFraction) / Double(total))
    }
}

enum ConversionError: LocalizedError {
    case tools(ToolError)
    case missingDonor
    case dngConvertFailed(source: URL, stderr: String)
    case spoofFailed(dng: URL, stderr: String)
    case outputDirectory(URL, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .tools(let e):
            return e.errorDescription
        case .missingDonor:
            return "Le template donor X2D est introuvable."
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
    let donorURL: URL?
    let options: ConversionOptions

    enum OverwriteStrategy { case skip, overwrite, suffix }
    var overwriteStrategy: OverwriteStrategy = .suffix

    init(mapping: CameraMapping, donorURL: URL?, options: ConversionOptions = .default) {
        self.mapping = mapping
        self.donorURL = donorURL
        self.options = options
    }

    private var effectiveDonorURL: URL? {
        donorURL ?? (BundledTools.hasEmbeddedX2DDonorTemplate ? BundledTools.embeddedX2DDonorTemplate : nil)
    }

    func convert(
        _ source: URL,
        progressHandler: ((String, Double) -> Void)? = nil
    ) async throws -> URL {
        let outputDir = source.deletingLastPathComponent()
            .appendingPathComponent(mapping.outputDirectoryName, isDirectory: true)

        do {
            try FileManager.default.createDirectory(
                at: outputDir, withIntermediateDirectories: true)
        } catch {
            throw ConversionError.outputDirectory(outputDir, underlying: error)
        }

        let outputFile = try nextOutputFile(for: source, in: outputDir)

        switch mapping.pipeline {
        case .nativeHasselbladToFuji:
            return try convertNativeHasselbladToFuji(
                source: source,
                outputFile: outputFile,
                progressHandler: progressHandler
            )
        case .leicaViaHasselbladToFuji:
            guard let donorURL = effectiveDonorURL else { throw ConversionError.missingDonor }
            return try convertLeicaViaHasselbladToFuji(
                source: source,
                donorURL: donorURL,
                outputFile: outputFile,
                progressHandler: progressHandler
            )
        case .nativeLeicaToHasselblad:
            guard let donorURL = effectiveDonorURL else { throw ConversionError.missingDonor }
            return try convertNativeLeicaToHasselblad(
                source: source,
                donorURL: donorURL,
                outputFile: outputFile,
                progressHandler: progressHandler
            )
        }
    }

    func convertBatch(_ sources: [URL]) -> AsyncThrowingStream<ConversionProgress, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try verifyRequiredTools()
                    for (index, source) in sources.enumerated() {
                        let output = try await convert(source) { phase, fraction in
                            continuation.yield(ConversionProgress(
                                processed: index,
                                total: sources.count,
                                currentPhase: phase,
                                currentFileFraction: max(0, min(1, fraction)),
                                lastOutput: nil
                            ))
                        }
                        continuation.yield(ConversionProgress(
                            processed: index + 1,
                            total: sources.count,
                            currentPhase: "DONE",
                            currentFileFraction: 0,
                            lastOutput: output
                        ))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func verifyRequiredTools() throws {
        switch mapping.pipeline {
        case .nativeHasselbladToFuji:
            try BundledTools.verifyAll()
        case .leicaViaHasselbladToFuji:
            try BundledTools.verifyAll()
            try BundledTools.verifyEmbeddedX2DDonorTemplate()
        case .nativeLeicaToHasselblad:
            try BundledTools.verifyExiftool()
            try BundledTools.verifyEmbeddedX2DDonorTemplate()
        }
    }

    private func nextOutputFile(for source: URL, in outputDir: URL) throws -> URL {
        let baseName = source.deletingPathExtension().lastPathComponent
        let ext = mapping.outputExtension
        var outputFile = outputDir.appendingPathComponent("\(baseName).\(ext)")

        if FileManager.default.fileExists(atPath: outputFile.path) {
            switch overwriteStrategy {
            case .skip:
                return outputFile
            case .overwrite:
                try? FileManager.default.removeItem(at: outputFile)
            case .suffix:
                var index = 1
                repeat {
                    outputFile = outputDir.appendingPathComponent(
                        "\(baseName)_converted\(index == 1 ? "" : "-\(index)").\(ext)"
                    )
                    index += 1
                } while FileManager.default.fileExists(atPath: outputFile.path)
            }
        }

        return outputFile
    }

    private func convertNativeHasselbladToFuji(
        source: URL,
        outputFile: URL,
        progressHandler: ((String, Double) -> Void)?
    ) throws -> URL {
        progressHandler?("CONVERTING WITH DNGLAB", 0.15)
        let dng = try run(BundledTools.dnglab, args: [
            "convert",
            "--compression", "lossless",
            source.path,
            outputFile.path,
        ])
        if dng.exitCode != 0 {
            throw ConversionError.dngConvertFailed(
                source: source,
                stderr: dng.stderr.isEmpty ? dng.stdout : dng.stderr
            )
        }
        progressHandler?("PATCHING FUJI TAGS", 0.8)
        let result = try spoofDNGIdentity(at: outputFile)
        progressHandler?("FINALIZING", 1.0)
        return result
    }

    private func convertLeicaViaHasselbladToFuji(
        source: URL,
        donorURL: URL,
        outputFile: URL,
        progressHandler: ((String, Double) -> Void)?
    ) throws -> URL {
        let sourceMetadata: LeicaSourceMetadata?
        if options.preserveOriginalLeicaBodyInfo {
            do {
                sourceMetadata = try LeicaSourceMetadataExtractor.extract(from: source, exiftoolURL: BundledTools.exiftool)
            } catch {
                FileHandle.standardError.write(
                    Data("Warning: impossible d'extraire les métadonnées Leica pour \(source.lastPathComponent): \(error.localizedDescription)\n".utf8)
                )
                sourceMetadata = nil
            }
        } else {
            sourceMetadata = nil
        }
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("2FujiRaw-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let intermediate3FR = tempRoot.appendingPathComponent("\(source.deletingPathExtension().lastPathComponent).3fr")
        progressHandler?("BUILDING X2D 3FR", 0.02)
        try LeicaX2DWriter.write(
            sourceURL: source,
            donorURL: donorURL,
            outputURL: intermediate3FR,
            progressHandler: { phase, fraction in
                progressHandler?(phase, min(0.72, fraction * 0.72))
            },
            options: .default
        )

        progressHandler?("CONVERTING 3FR WITH DNGLAB", 0.8)
        let dng = try run(BundledTools.dnglab, args: [
            "convert",
            "--compression", "lossless",
            intermediate3FR.path,
            outputFile.path,
        ])
        if dng.exitCode != 0 {
            throw ConversionError.dngConvertFailed(
                source: intermediate3FR,
                stderr: dng.stderr.isEmpty ? dng.stdout : dng.stderr
            )
        }

        progressHandler?("PATCHING FUJI TAGS", 0.92)
        let result = try spoofDNGIdentity(
            at: outputFile,
            sourceLeicaModel: sourceMetadata?.model
        )
        progressHandler?("FINALIZING", 1.0)
        return result
    }

    private func convertNativeLeicaToHasselblad(
        source: URL,
        donorURL: URL,
        outputFile: URL,
        progressHandler: ((String, Double) -> Void)?
    ) throws -> URL {
        try LeicaX2DWriter.write(
            sourceURL: source,
            donorURL: donorURL,
            outputURL: outputFile,
            progressHandler: progressHandler,
            options: options
        )
        return outputFile
    }

    private func spoofDNGIdentity(
        at outputFile: URL,
        sourceLeicaModel: String? = nil
    ) throws -> URL {
        var args = [
            "-Make=\(mapping.targetMake ?? "FUJIFILM")",
            "-Model=\((options.preserveOriginalLeicaBodyInfo ? sourceLeicaModel : nil) ?? (mapping.targetModel ?? "GFX 100S II"))",
            "-UniqueCameraModel=\(mapping.targetUniqueCameraModel ?? "Fujifilm GFX 100S II")",
            "-PreviewApplicationName=2FujiRaw",
            "-PreviewApplicationVersion=0.1.0",
            "-PreviewDateTime=now",
            "-PreviewColorSpace=sRGB",
        ]
        args.append("-overwrite_original")
        args.append(outputFile.path)
        let exif = try run(BundledTools.exiftool, args: args)
        if exif.exitCode != 0 {
            throw ConversionError.spoofFailed(
                dng: outputFile,
                stderr: exif.stderr.isEmpty ? exif.stdout : exif.stderr
            )
        }
        return outputFile
    }

    private func run(_ binary: URL, args: [String]) throws -> (stdout: String, stderr: String, exitCode: Int32) {
        let result = try ProcessRunner.run(executableURL: binary, arguments: args)
        let out = String(data: result.stdout, encoding: .utf8) ?? ""
        let err = String(data: result.stderr, encoding: .utf8) ?? ""
        return (out, err, result.exitCode)
    }
}
