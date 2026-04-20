import Foundation

enum LeicaX2DWriterError: LocalizedError {
    case invalidDonorLayout(String)
    case missingPreviewIFD
    case rawPayloadSizeMismatch(Int, Int)
    case headerOverflow(Int, Int)
    case rawOverflow(Int, Int)

    var errorDescription: String? {
        switch self {
        case .invalidDonorLayout(let message):
            return message
        case .missingPreviewIFD:
            return "IFD preview introuvable dans le DNG source."
        case .rawPayloadSizeMismatch(let actual, let expected):
            return "Taille payload RAW invalide: \(actual) != \(expected)"
        case .headerOverflow(let actual, let limit):
            return "L'en-tête dépasse l'offset RAW du donor: \(actual) > \(limit)"
        case .rawOverflow(let actual, let limit):
            return "Le payload RAW dépasse l'offset preview: \(actual) > \(limit)"
        }
    }
}

struct LeicaX2DWriter {
    static let donorFullSize = (width: 11904, height: 8842)
    static let donorRawLength = donorFullSize.width * donorFullSize.height * 2
    static let previewLongEdge = 3888

    static func write(
        sourceURL: URL,
        donorURL: URL,
        outputURL: URL,
        progressHandler: ((String, Double) -> Void)? = nil,
        options: ConversionOptions = .default
    ) throws {
        progressHandler?("READING SOURCE GEOMETRY", 0.06)
        let geometry = try LeicaRawProcessing.readSourceGeometry(sourceURL: sourceURL)
        progressHandler?("READING SOURCE METADATA", 0.14)
        let sourceMetadata = try LeicaSourceMetadataExtractor.extract(from: sourceURL, exiftoolURL: BundledTools.exiftool)
        progressHandler?("BUILDING PREVIEW", 0.24)
        let previewJPEG = try buildPreview(sourceURL: sourceURL, geometry: geometry)
        progressHandler?("ANALYZING DONOR LAYOUT", 0.34)
        let layout = try outputLayout(donorURL: donorURL, fullSize: geometry.fullSize, previewSize: previewJPEG.count)

        progressHandler?("PATCHING X2D HEADER", 0.48)
        var headerBuilder = try LeicaHeaderBuilder(
            donorURL: donorURL,
            sourceURL: sourceURL,
            layout: layout,
            geometry: geometry,
            options: options
        )
        let header = try headerBuilder.build(sourceMetadata: sourceMetadata)

        progressHandler?("EXTRACTING BAYER PLANES", 0.66)
        let planes = try LeicaRawProcessing.extractLeicaPlanes(sourceURL: sourceURL, geometry: geometry)
        progressHandler?("ASSEMBLING RAW PAYLOAD", 0.82)
        let rawPayload = try LeicaRawProcessing.assembleRawPayload(planes: planes, geometry: geometry)
        guard rawPayload.count == layout.rawLength else {
            throw LeicaX2DWriterError.rawPayloadSizeMismatch(rawPayload.count, layout.rawLength)
        }

        progressHandler?("WRITING 3FR", 0.93)
        var out = Data(capacity: layout.fileSize)
        out.append(header)
        if out.count > layout.rawOffset {
            throw LeicaX2DWriterError.headerOverflow(out.count, layout.rawOffset)
        }
        if out.count < layout.rawOffset {
            out.append(Data(repeating: 0, count: layout.rawOffset - out.count))
        }
        out.append(rawPayload)
        if out.count > layout.previewOffset {
            throw LeicaX2DWriterError.rawOverflow(out.count, layout.previewOffset)
        }
        if out.count < layout.previewOffset {
            out.append(Data(repeating: 0, count: layout.previewOffset - out.count))
        }
        out.append(previewJPEG)
        if previewJPEG.count < layout.previewSlot {
            out.append(Data(repeating: 0, count: layout.previewSlot - previewJPEG.count))
        }

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try out.write(to: outputURL, options: .atomic)
        progressHandler?("DONE", 1.0)
    }

    static func donorLayout(donorURL: URL) throws -> LeicaX2DOutputLayout {
        let donor = try TIFFFile(url: donorURL)
        let ifd0 = try donor.ifdMap(at: donor.rootIFDOffset())
        guard
            let subIFDs = ifd0[TIFFTag.subIFDs],
            let rawIFDOffset = try donor.longValues(for: subIFDs).first
        else {
            throw LeicaX2DWriterError.invalidDonorLayout("SubIFD donor introuvable.")
        }
        let rawIFD = try donor.ifdMap(at: Int(rawIFDOffset))
        let rawOffset = Int(rawIFD[TIFFTag.stripOffsets]?.value ?? 0)
        let rawLength = Int(rawIFD[TIFFTag.stripByteCounts]?.value ?? 0)
        let previewOffset = Int(ifd0[TIFFTag.stripOffsets]?.value ?? 0)
        let previewSlot = Int(ifd0[TIFFTag.stripByteCounts]?.value ?? 0)

        guard rawLength == donorRawLength else {
            throw LeicaX2DWriterError.invalidDonorLayout("Longueur RAW donor inattendue: \(rawLength)")
        }
        guard rawOffset >= 8 else {
            throw LeicaX2DWriterError.invalidDonorLayout("Offset RAW donor inattendu: \(rawOffset)")
        }
        guard previewOffset > rawOffset + rawLength else {
            throw LeicaX2DWriterError.invalidDonorLayout("Le preview donor doit suivre le payload RAW.")
        }

        return LeicaX2DOutputLayout(
            rawOffset: rawOffset,
            rawLength: rawLength,
            previewOffset: previewOffset,
            previewSlot: previewSlot,
            fileSize: donor.data.count
        )
    }

    static func outputLayout(
        donorURL: URL,
        fullSize: (width: Int, height: Int),
        previewSize: Int
    ) throws -> LeicaX2DOutputLayout {
        let donor = try donorLayout(donorURL: donorURL)
        let pixelCount = fullSize.width.multipliedReportingOverflow(by: fullSize.height)
        guard !pixelCount.overflow else {
            throw LeicaX2DWriterError.invalidDonorLayout("Dimensions source trop grandes pour calculer le payload RAW.")
        }
        let rawLengthResult = pixelCount.partialValue.multipliedReportingOverflow(by: 2)
        guard !rawLengthResult.overflow else {
            throw LeicaX2DWriterError.invalidDonorLayout("Longueur RAW source trop grande.")
        }
        let rawLength = rawLengthResult.partialValue
        let previewOffset = alignUp(donor.rawOffset + rawLength, alignment: 4096)
        guard previewOffset >= donor.rawOffset + rawLength else {
            throw LeicaX2DWriterError.invalidDonorLayout("Overflow lors du calcul de l'offset preview.")
        }
        return LeicaX2DOutputLayout(
            rawOffset: donor.rawOffset,
            rawLength: rawLength,
            previewOffset: previewOffset,
            previewSlot: previewSize,
            fileSize: previewOffset + previewSize
        )
    }

    static func buildPreview(sourceURL: URL, geometry: LeicaSourceGeometry) throws -> Data {
        let source = try TIFFFile(url: sourceURL)
        let ifd0 = try source.ifdMap(at: source.rootIFDOffset())
        guard
            let subIFDsEntry = ifd0[TIFFTag.subIFDs]
        else {
            throw LeicaX2DWriterError.missingPreviewIFD
        }
        let subIFDs = try source.longValues(for: subIFDsEntry)
        guard subIFDs.count > 2 else {
            throw LeicaX2DWriterError.missingPreviewIFD
        }
        let previewIFD = try source.ifdMap(at: Int(subIFDs[2]))
        let previewStart = Int(previewIFD[TIFFTag.stripOffsets]?.value ?? 0)
        let previewLength = Int(previewIFD[TIFFTag.stripByteCounts]?.value ?? 0)
        guard previewStart >= 0, previewLength > 0, previewStart <= source.data.count, previewLength <= source.data.count - previewStart else {
            throw LeicaX2DWriterError.missingPreviewIFD
        }
        let previewBytes = source.data.subdata(in: previewStart..<(previewStart + previewLength))

        let cropWidth = geometry.cropSize.width
        let cropHeight = geometry.cropSize.height
        let targetWidth: Int
        let targetHeight: Int
        if cropWidth >= cropHeight {
            targetWidth = previewLongEdge
            targetHeight = Int((Double(previewLongEdge) * Double(cropHeight) / Double(cropWidth)).rounded())
        } else {
            targetHeight = previewLongEdge
            targetWidth = Int((Double(previewLongEdge) * Double(cropWidth) / Double(cropHeight)).rounded())
        }

        guard let magick = resolveMagick() else {
            return previewBytes
        }

        do {
            let result = try ProcessRunner.run(
                executableURL: magick,
                arguments: ["jpg:-", "-resize", "\(targetWidth)x\(targetHeight)", "-quality", "92", "jpg:-"],
                input: previewBytes
            )
            if result.exitCode == 0 {
                return result.stdout
            }
            return previewBytes
        } catch {
            return previewBytes
        }
    }

    static func resolveMagick() -> URL? {
        let candidates = [
            "/opt/homebrew/bin/magick",
            "/usr/local/bin/magick",
            "/usr/bin/magick",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    static func alignUp(_ value: Int, alignment: Int) -> Int {
        ((value + alignment - 1) / alignment) * alignment
    }
}
