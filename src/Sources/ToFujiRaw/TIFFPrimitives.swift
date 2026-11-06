import Foundation

enum TIFFError: LocalizedError {
    case notLittleEndian(URL)
    case malformedOffset(URL, Int)
    case malformedIFD(URL, Int)
    case payloadOutOfBounds(URL, UInt16, Int, Int)
    case payloadSizeMismatch(tag: UInt16, expected: Int, actual: Int)
    case unexpectedLongPayload(tag: UInt16)
    case unsupportedScalarPatch(tag: UInt16, type: UInt16, count: UInt32)
    case headerSpaceExhausted(requested: Int, limit: Int)

    var errorDescription: String? {
        switch self {
        case .notLittleEndian(let url):
            return "\(url.path) n'est pas un TIFF little-endian."
        case .malformedOffset(let url, let offset):
            return "\(url.path) contient un offset TIFF invalide: \(offset)."
        case .malformedIFD(let url, let offset):
            return "\(url.path) contient une IFD TIFF invalide à l'offset \(offset)."
        case .payloadOutOfBounds(let url, let tag, let offset, let size):
            return String(format: "%@ contient un payload hors limites pour le tag 0x%04X (offset=%d size=%d).", url.path, tag, offset, size)
        case .payloadSizeMismatch(let tag, let expected, let actual):
            return String(format: "Payload TIFF invalide pour le tag 0x%04X : %d != %d", tag, actual, expected)
        case .unexpectedLongPayload(let tag):
            return String(format: "Payload LONG inattendu pour le tag 0x%04X", tag)
        case .unsupportedScalarPatch(let tag, let type, let count):
            return String(format: "Patch scalaire non supporté pour tag 0x%04X (type=%d count=%d)", tag, type, count)
        case .headerSpaceExhausted(let requested, let limit):
            return "Pas assez d'espace d'en-tête pour allouer \(requested) octets avant \(limit)."
        }
    }
}

enum TIFFType {
    static let byte: UInt16 = 1
    static let ascii: UInt16 = 2
    static let short: UInt16 = 3
    static let long: UInt16 = 4
    static let rational: UInt16 = 5
    static let undefined: UInt16 = 7
    static let srational: UInt16 = 10

    static func size(of tagType: UInt16, count: UInt32) -> Int {
        let unit: Int
        switch tagType {
        case byte, ascii, undefined:
            unit = 1
        case short:
            unit = 2
        case long:
            unit = 4
        case rational, srational:
            unit = 8
        default:
            unit = 1
        }
        return unit * Int(count)
    }
}

struct TIFFEntry: Hashable {
    let tag: UInt16
    let type: UInt16
    let count: UInt32
    let value: UInt32
    let entryOffset: Int
}

struct TIFFFile {
    static let maxIFDEntries = 10_000

    let url: URL
    let data: Data

    init(url: URL) throws {
        self.url = url
        self.data = try Data(contentsOf: url)
        guard data.count >= 2, data[0] == 0x49, data[1] == 0x49 else {
            throw TIFFError.notLittleEndian(url)
        }
    }

    func u16(at offset: Int) -> UInt16? {
        data.readUInt16LE(at: offset)
    }

    func u32(at offset: Int) -> UInt32? {
        data.readUInt32LE(at: offset)
    }

    func rootIFDOffset() throws -> Int {
        guard let rootOffset = u32(at: 4) else {
            throw TIFFError.malformedOffset(url, 4)
        }
        let offset = Int(rootOffset)
        guard offset >= 0, offset < data.count else {
            throw TIFFError.malformedOffset(url, offset)
        }
        return offset
    }

    func ifdEntries(at offset: Int) throws -> [TIFFEntry] {
        guard offset >= 0, offset + 2 <= data.count else {
            throw TIFFError.malformedOffset(url, offset)
        }
        guard let countValue = u16(at: offset) else {
            throw TIFFError.malformedIFD(url, offset)
        }
        let count = Int(countValue)
        guard count <= Self.maxIFDEntries else {
            throw TIFFError.malformedIFD(url, offset)
        }
        let entriesStart = offset + 2
        let entriesByteCount = count * 12
        guard entriesByteCount <= data.count - entriesStart else {
            throw TIFFError.malformedIFD(url, offset)
        }

        return try (0..<count).map { index in
            let entryOffset = offset + 2 + index * 12
            guard
                let tag = u16(at: entryOffset),
                let type = u16(at: entryOffset + 2),
                let count = u32(at: entryOffset + 4),
                let value = u32(at: entryOffset + 8)
            else {
                throw TIFFError.malformedIFD(url, offset)
            }
            return TIFFEntry(
                tag: tag,
                type: type,
                count: count,
                value: value,
                entryOffset: entryOffset
            )
        }
    }

    func ifdMap(at offset: Int) throws -> [UInt16: TIFFEntry] {
        Dictionary(uniqueKeysWithValues: try ifdEntries(at: offset).map { ($0.tag, $0) })
    }

    func payloadBytes(for entry: TIFFEntry) throws -> Data {
        let size = TIFFType.size(of: entry.type, count: entry.count)
        if size <= 4 {
            var value = entry.value.littleEndian
            let full = Data(bytes: &value, count: 4)
            return full.prefix(size)
        }
        let start = Int(entry.value)
        guard start >= 0, size >= 0, start <= data.count, size <= data.count - start else {
            throw TIFFError.payloadOutOfBounds(url, entry.tag, start, size)
        }
        return data.subdata(in: start..<(start + size))
    }

    func longValues(for entry: TIFFEntry) throws -> [UInt32] {
        let payload = try payloadBytes(for: entry)
        let expected = Int(entry.count) * 4
        guard payload.count == expected else {
            throw TIFFError.unexpectedLongPayload(tag: entry.tag)
        }
        return stride(from: 0, to: payload.count, by: 4).map { offset in
            (UInt32(payload[offset + 3]) << 24)
            | (UInt32(payload[offset + 2]) << 16)
            | (UInt32(payload[offset + 1]) << 8)
            | UInt32(payload[offset])
        }
    }
}

extension Data {
    mutating func replaceBytes(at offset: Int, with replacement: Data) {
        replaceSubrange(offset..<(offset + replacement.count), with: replacement)
    }

    mutating func patchLongInline(_ entry: TIFFEntry, value: UInt32) {
        var le = value.littleEndian
        let raw = Data(bytes: &le, count: 4)
        replaceBytes(at: entry.entryOffset + 8, with: raw)
    }

    mutating func patchShortInline(_ entry: TIFFEntry, value: UInt16) {
        var le = value.littleEndian
        var raw = Data(bytes: &le, count: 2)
        raw.append(contentsOf: [0, 0])
        replaceBytes(at: entry.entryOffset + 8, with: raw)
    }

    mutating func patchASCII(_ entry: TIFFEntry, text: String) throws {
        let count = Int(entry.count)
        let payload = text.data(using: .ascii, allowLossyConversion: true) ?? Data()
        let encoded = payload.prefix(Swift.max(0, count - 1))
        var final = Data(encoded)
        final.append(0)
        if final.count < count {
            final.append(Data(repeating: 0, count: count - final.count))
        }
        if count <= 4 {
            if final.count < 4 {
                final.append(Data(repeating: 0, count: 4 - final.count))
            }
            replaceBytes(at: entry.entryOffset + 8, with: final.prefix(4))
        } else {
            replaceBytes(at: Int(entry.value), with: final.prefix(count))
        }
    }

    mutating func patchScalarInline(_ entry: TIFFEntry, value: UInt32) throws {
        switch (entry.type, entry.count) {
        case (TIFFType.short, 1):
            patchShortInline(entry, value: UInt16(truncatingIfNeeded: value))
        case (TIFFType.long, 1):
            patchLongInline(entry, value: value)
        default:
            throw TIFFError.unsupportedScalarPatch(tag: entry.tag, type: entry.type, count: entry.count)
        }
    }

    mutating func patchRational(_ entry: TIFFEntry, numerator: Int32, denominator: Int32, signed: Bool = false) {
        var raw = Data()
        if signed {
            var num = numerator.littleEndian
            var den = denominator.littleEndian
            raw.append(Data(bytes: &num, count: 4))
            raw.append(Data(bytes: &den, count: 4))
        } else {
            var num = UInt32(bitPattern: numerator).littleEndian
            var den = UInt32(bitPattern: denominator).littleEndian
            raw.append(Data(bytes: &num, count: 4))
            raw.append(Data(bytes: &den, count: 4))
        }
        replaceBytes(at: Int(entry.value), with: raw)
    }

    mutating func patchEntryPayload(_ entry: TIFFEntry, raw: Data) throws {
        let size = TIFFType.size(of: entry.type, count: entry.count)
        guard raw.count == size else {
            throw TIFFError.payloadSizeMismatch(tag: entry.tag, expected: size, actual: raw.count)
        }
        if size <= 4 {
            replaceBytes(at: entry.entryOffset + 8, with: raw + Data(repeating: 0, count: 4 - raw.count))
        } else {
            replaceBytes(at: Int(entry.value), with: raw)
        }
    }

    func entryPayload(_ entry: TIFFEntry) -> Data {
        let size = TIFFType.size(of: entry.type, count: entry.count)
        if size <= 4 {
            return subdata(in: (entry.entryOffset + 8)..<(entry.entryOffset + 8 + size))
        }
        return subdata(in: Int(entry.value)..<(Int(entry.value) + size))
    }

    mutating func zeroRegion(start: Int, length: Int) {
        replaceBytes(at: start, with: Data(repeating: 0, count: length))
    }

    mutating func rewriteIFDWithoutTags(at ifdOffset: Int, dropTags: Set<UInt16>) {
        let count = Int(readUInt16LE(at: ifdOffset) ?? 0)
        var kept: [TIFFEntry] = []
        for index in 0..<count {
            let entryOffset = ifdOffset + 2 + index * 12
            let entry = TIFFEntry(
                tag: readUInt16LE(at: entryOffset) ?? 0,
                type: readUInt16LE(at: entryOffset + 2) ?? 0,
                count: readUInt32LE(at: entryOffset + 4) ?? 0,
                value: readUInt32LE(at: entryOffset + 8) ?? 0,
                entryOffset: entryOffset
            )
            if !dropTags.contains(entry.tag) {
                kept.append(entry)
            }
        }

        var countLE = UInt16(kept.count).littleEndian
        replaceBytes(at: ifdOffset, with: Data(bytes: &countLE, count: 2))

        var cursor = ifdOffset + 2
        for entry in kept {
            var raw = Data()
            var tag = entry.tag.littleEndian
            var type = entry.type.littleEndian
            var count = entry.count.littleEndian
            var value = entry.value.littleEndian
            raw.append(Data(bytes: &tag, count: 2))
            raw.append(Data(bytes: &type, count: 2))
            raw.append(Data(bytes: &count, count: 4))
            raw.append(Data(bytes: &value, count: 4))
            replaceBytes(at: cursor, with: raw)
            cursor += 12
        }
        let nextIFDOffsetLocation = ifdOffset + 2 + count * 12
        let nextIFD = readUInt32LE(at: nextIFDOffsetLocation) ?? 0
        var nextLE = nextIFD.littleEndian
        replaceBytes(at: cursor, with: Data(bytes: &nextLE, count: 4))
    }

    mutating func allocateHeaderBytes(nextFreeOffset: Int, limitOffset: Int, raw: Data) throws -> Int {
        let end = nextFreeOffset + raw.count
        guard end <= limitOffset else {
            throw TIFFError.headerSpaceExhausted(requested: raw.count, limit: limitOffset)
        }
        replaceBytes(at: nextFreeOffset, with: raw)
        return nextFreeOffset
    }

    func maxHeaderPayloadEnd(ifdMaps: [[UInt16: TIFFEntry]], rootIFDOffset: Int) -> Int {
        var maxEnd = rootIFDOffset
        for ifd in ifdMaps {
            maxEnd = Swift.max(maxEnd, rootIFDOffset + 2 + ifd.count * 12 + 4)
            for entry in ifd.values {
                let size = TIFFType.size(of: entry.type, count: entry.count)
                if size > 4 {
                    maxEnd = Swift.max(maxEnd, Int(entry.value) + size)
                }
            }
        }
        return maxEnd
    }
}

extension Data {
    mutating func appendLE(_ value: UInt16) {
        var le = value.littleEndian
        append(Data(bytes: &le, count: 2))
    }

    func readUInt16LE(at offset: Int) -> UInt16? {
        guard offset + 2 <= count else { return nil }
        return (UInt16(self[offset + 1]) << 8) | UInt16(self[offset])
    }

    func readUInt32LE(at offset: Int) -> UInt32? {
        guard offset + 4 <= count else { return nil }
        return (UInt32(self[offset + 3]) << 24)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 1]) << 8)
            | UInt32(self[offset])
    }
}
