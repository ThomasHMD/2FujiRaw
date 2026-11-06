import Foundation

enum LeicaRawProcessingError: LocalizedError {
    case missingRawIFD(URL)
    case missingDimensions(URL)
    case unsupportedCFAPattern(UInt8)
    case invalidPlaneDimensions
    case invalidPackedRowLength

    var errorDescription: String? {
        switch self {
        case .missingRawIFD(let url):
            return "Impossible de lire l'IFD RAW dans \(url.path)."
        case .missingDimensions(let url):
            return "Dimensions RAW manquantes ou invalides dans \(url.path)."
        case .unsupportedCFAPattern(let value):
            return "Motif CFA non supporté: \(value)"
        case .invalidPlaneDimensions:
            return "Dimensions des plans Bayer invalides."
        case .invalidPackedRowLength:
            return "Longueur de ligne RAW packée invalide."
        }
    }
}

struct LeicaSourceGeometry {
    let fullSize: (width: Int, height: Int)
    let cropOrigin: (x: Int, y: Int)
    let cropSize: (width: Int, height: Int)
    let activeSize: (width: Int, height: Int)
    let cfaTopLeft: UInt8
    let blackLevel: Int
    let whiteLevel: Int
}

enum LeicaRawProcessing {
    static let donorBlack = 4096
    static let donorWhite = 65535

    static let cfaRGGB: UInt8 = 0
    static let cfaBGGR: UInt8 = 2

    static func readSourceGeometry(sourceURL: URL) throws -> LeicaSourceGeometry {
        let source = try TIFFFile(url: sourceURL)
        let ifd0 = try source.ifdMap(at: source.rootIFDOffset())
        guard
            let subIFDs = ifd0[TIFFTag.subIFDs],
            let rawIFDOffset = try source.longValues(for: subIFDs).first
        else {
            throw LeicaRawProcessingError.missingRawIFD(sourceURL)
        }
        let rawIFD = try source.ifdMap(at: Int(rawIFDOffset))

        let fullWidth = Int(rawIFD[TIFFTag.imageWidth]?.value ?? 0)
        let fullHeight = Int(rawIFD[TIFFTag.imageHeight]?.value ?? 0)
        guard fullWidth > 0, fullHeight > 0 else {
            throw LeicaRawProcessingError.missingDimensions(sourceURL)
        }

        let cropOriginBytes = try rawIFD[TIFFTag.defaultCropOrigin].map { try source.payloadBytes(for: $0) } ?? Data()
        let cropSizeBytes = try rawIFD[TIFFTag.defaultCropSize].map { try source.payloadBytes(for: $0) } ?? Data()

        let cropX = cropOriginBytes.readUInt16LE(at: 0).map(Int.init) ?? 0
        let cropY = cropOriginBytes.readUInt16LE(at: 2).map(Int.init) ?? 0
        let cropWidth = cropSizeBytes.readUInt16LE(at: 0).map(Int.init) ?? fullWidth
        let cropHeight = cropSizeBytes.readUInt16LE(at: 2).map(Int.init) ?? fullHeight

        let activeSize: (width: Int, height: Int)
        if let activeArea = rawIFD[TIFFTag.activeArea] {
            let payload = try source.payloadBytes(for: activeArea)
            let top = Int(payload.readUInt16LE(at: 0) ?? 0)
            let left = Int(payload.readUInt16LE(at: 2) ?? 0)
            let bottom = Int(payload.readUInt16LE(at: 4) ?? UInt16(fullHeight))
            let right = Int(payload.readUInt16LE(at: 6) ?? UInt16(fullWidth))
            activeSize = (right - left, bottom - top)
        } else {
            activeSize = (fullWidth, fullHeight)
        }

        let cfaTopLeft = rawIFD[TIFFTag.cfaPattern]
            .flatMap { try? source.payloadBytes(for: $0).first } ?? cfaBGGR

        let blackLevel: Int
        if let blackEntry = rawIFD[TIFFTag.blackLevel] {
            let payload = try source.payloadBytes(for: blackEntry)
            if blackEntry.type == TIFFType.short {
                blackLevel = Int(payload.readUInt16LE(at: 0) ?? 512)
            } else {
                blackLevel = Int(payload.readUInt32LE(at: 0) ?? 512)
            }
        } else {
            blackLevel = 512
        }

        let whiteLevel: Int
        if let whiteEntry = rawIFD[TIFFTag.whiteLevel] {
            let payload = try source.payloadBytes(for: whiteEntry)
            whiteLevel = Int(payload.readUInt32LE(at: 0) ?? 16383)
        } else {
            whiteLevel = 16383
        }

        return LeicaSourceGeometry(
            fullSize: (fullWidth, fullHeight),
            cropOrigin: (cropX, cropY),
            cropSize: (cropWidth, cropHeight),
            activeSize: activeSize,
            cfaTopLeft: cfaTopLeft,
            blackLevel: blackLevel,
            whiteLevel: whiteLevel
        )
    }

    static func extractLeicaPlanes(sourceURL: URL, geometry: LeicaSourceGeometry) throws -> [[UInt16]] {
        let source = try TIFFFile(url: sourceURL)
        let ifd0 = try source.ifdMap(at: source.rootIFDOffset())
        guard
            let subIFDs = ifd0[TIFFTag.subIFDs],
            let rawIFDOffset = try source.longValues(for: subIFDs).first
        else {
            throw LeicaRawProcessingError.missingRawIFD(sourceURL)
        }
        let rawIFD = try source.ifdMap(at: Int(rawIFDOffset))
        let stripOffset = Int(rawIFD[TIFFTag.stripOffsets]?.value ?? 0)
        let stripLength = Int(rawIFD[TIFFTag.stripByteCounts]?.value ?? 0)

        let fullWidth = geometry.fullSize.width
        let fullHeight = geometry.fullSize.height
        let rowBytes = fullWidth * 14 / 8
        guard stripOffset + stripLength <= source.data.count else {
            throw LeicaRawProcessingError.invalidPackedRowLength
        }
        let raw = source.data.subdata(in: stripOffset..<(stripOffset + stripLength))

        let planeWidth = fullWidth / 2
        let planeHeight = fullHeight / 2
        var planes = Array(
            repeating: Array(repeating: UInt16(0), count: planeWidth * planeHeight),
            count: 4
        )

        for y in 0..<fullHeight {
            let rowStart = y * rowBytes
            let rowEnd = rowStart + rowBytes
            guard rowEnd <= raw.count else {
                throw LeicaRawProcessingError.invalidPackedRowLength
            }
            let packedRow = raw.subdata(in: rowStart..<rowEnd)
            let row = try unpackRow14BE(packedRow, width: fullWidth)
            for x in 0..<fullWidth {
                let planeIndex = ((y & 1) << 1) | (x & 1)
                let dstIndex = (y / 2) * planeWidth + (x / 2)
                planes[planeIndex][dstIndex] = UInt16(remapToDonorRange(
                    value: Int(row[x]),
                    black: geometry.blackLevel,
                    white: geometry.whiteLevel
                ))
            }
        }

        return planes
    }

    static func assembleRawPayload(planes: [[UInt16]], geometry: LeicaSourceGeometry) throws -> Data {
        let fullWidth = geometry.fullSize.width
        let fullHeight = geometry.fullSize.height
        let planeWidth = fullWidth / 2
        let planeHeight = fullHeight / 2

        guard planes.count == 4, planes.allSatisfy({ $0.count == planeWidth * planeHeight }) else {
            throw LeicaRawProcessingError.invalidPlaneDimensions
        }

        let evenRow: (Int, Int)
        let oddRow: (Int, Int)
        switch geometry.cfaTopLeft {
        case cfaBGGR:
            evenRow = (3, 1)
            oddRow = (2, 0)
        case cfaRGGB:
            evenRow = (0, 1)
            oddRow = (2, 3)
        default:
            throw LeicaRawProcessingError.unsupportedCFAPattern(geometry.cfaTopLeft)
        }

        var output = Data(capacity: fullWidth * fullHeight * 2)
        for y in 0..<fullHeight {
            let rowPlanes = (y & 1) == 0 ? evenRow : oddRow
            let planeRowIndex = y / 2
            for x in 0..<planeWidth {
                let baseIndex = planeRowIndex * planeWidth + x
                let sampleA = planes[rowPlanes.0][baseIndex]
                let sampleB = planes[rowPlanes.1][baseIndex]
                output.appendLE(sampleA)
                output.appendLE(sampleB)
            }
        }
        return output
    }

    static func remapToDonorRange(value: Int, black: Int, white: Int) -> Int {
        let clamped = Swift.max(black, Swift.min(white, value))
        let scale = Double(clamped - black) / Double(white - black)
        let mapped = Double(donorBlack) + scale * Double(donorWhite - donorBlack)
        return Swift.max(0, Swift.min(65535, Int(mapped.rounded())))
    }

    static func unpackRow14BE(_ rowBytes: Data, width: Int) throws -> [UInt16] {
        var values: [UInt16] = []
        values.reserveCapacity(width)
        var index = 0
        while index + 7 <= rowBytes.count {
            let base = rowBytes.startIndex + index
            let c0 = UInt16(rowBytes[base + 0])
            let c1 = UInt16(rowBytes[base + 1])
            let c2 = UInt16(rowBytes[base + 2])
            let c3 = UInt16(rowBytes[base + 3])
            let c4 = UInt16(rowBytes[base + 4])
            let c5 = UInt16(rowBytes[base + 5])
            let c6 = UInt16(rowBytes[base + 6])

            values.append((c0 << 6) | (c1 >> 2))
            values.append(((c1 & 0x03) << 12) | (c2 << 4) | (c3 >> 4))
            values.append(((c3 & 0x0F) << 10) | (c4 << 2) | (c5 >> 6))
            values.append(((c5 & 0x3F) << 8) | c6)
            index += 7
        }
        guard values.count == width else {
            throw LeicaRawProcessingError.invalidPackedRowLength
        }
        return values
    }
}
