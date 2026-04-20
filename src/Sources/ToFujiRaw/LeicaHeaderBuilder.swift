import Foundation

struct LeicaX2DOutputLayout {
    let rawOffset: Int
    let rawLength: Int
    let previewOffset: Int
    let previewSlot: Int
    let fileSize: Int
}

enum HeaderBuildError: LocalizedError {
    case missingIFD(UInt16)
    case payloadMismatch(tag: UInt16)
    case invalidMakerNote

    var errorDescription: String? {
        switch self {
        case .missingIFD(let tag):
            return String(format: "IFD/tag manquant: 0x%04X", tag)
        case .payloadMismatch(let tag):
            return String(format: "Payload invalide pour tag 0x%04X", tag)
        case .invalidMakerNote:
            return "MakerNote Hasselblad invalide."
        }
    }
}

struct LeicaHeaderBuilder {
    static let dropMakerNoteTags: Set<UInt16> = [HasselbladMakerNoteTag.hncsBlocker]
    static let outputCFARGGBBytes = Data([0x00, 0x01, 0x01, 0x02])

    let donor: TIFFFile
    let source: TIFFFile
    let layout: LeicaX2DOutputLayout
    let geometry: LeicaSourceGeometry
    let options: ConversionOptions

    private var header: Data
    private let ifd0: [UInt16: TIFFEntry]
    private let rawIFD: [UInt16: TIFFEntry]
    private let exifIFD: [UInt16: TIFFEntry]
    private let sourceIFD0: [UInt16: TIFFEntry]
    private let sourceRawIFD: [UInt16: TIFFEntry]
    private var nextFree: Int

    init(
        donorURL: URL,
        sourceURL: URL,
        layout: LeicaX2DOutputLayout,
        geometry: LeicaSourceGeometry,
        options: ConversionOptions
    ) throws {
        let donor = try TIFFFile(url: donorURL)
        let source = try TIFFFile(url: sourceURL)
        let donorRootIFDOffset = try donor.rootIFDOffset()
        let ifd0 = try donor.ifdMap(at: donorRootIFDOffset)
        guard
            let donorSubIFDs = ifd0[TIFFTag.subIFDs],
            let rawIFDOffset = try donor.longValues(for: donorSubIFDs).first,
            let exifEntry = ifd0[TIFFTag.exifIFD]
        else {
            throw HeaderBuildError.missingIFD(TIFFTag.subIFDs)
        }
        let rawIFD = try donor.ifdMap(at: Int(rawIFDOffset))
        let exifIFD = try donor.ifdMap(at: Int(exifEntry.value))

        let sourceIFD0 = try source.ifdMap(at: source.rootIFDOffset())
        guard
            let sourceSubIFDs = sourceIFD0[TIFFTag.subIFDs],
            let sourceRawIFDOffset = try source.longValues(for: sourceSubIFDs).first
        else {
            throw HeaderBuildError.missingIFD(TIFFTag.subIFDs)
        }
        let sourceRawIFD = try source.ifdMap(at: Int(sourceRawIFDOffset))

        self.donor = donor
        self.source = source
        self.layout = layout
        self.geometry = geometry
        self.options = options
        self.header = donor.data.prefix(layout.rawOffset)
        self.ifd0 = ifd0
        self.rawIFD = rawIFD
        self.exifIFD = exifIFD
        self.sourceIFD0 = sourceIFD0
        self.sourceRawIFD = sourceRawIFD
        self.nextFree = self.header.maxHeaderPayloadEnd(
            ifdMaps: [ifd0, rawIFD, exifIFD],
            rootIFDOffset: donorRootIFDOffset
        )
    }

    mutating func build(sourceMetadata: LeicaSourceMetadata) throws -> Data {
        try patchGeometry(sourceMetadata: sourceMetadata)
        try patchBodyDisplayName(sourceMetadata: sourceMetadata)
        try patchDateTime(sourceMetadata: sourceMetadata)
        try patchExif(sourceMetadata: sourceMetadata)
        try patchWhiteBalance()
        try patchLensIdentity(sourceMetadata: sourceMetadata)
        try rewriteRawIFD()
        try patchMakerNote()
        try patchXMP()
        return header
    }

    private mutating func patchBodyDisplayName(sourceMetadata: LeicaSourceMetadata) throws {
        guard options.preserveOriginalLeicaBodyInfo,
              let model = sourceMetadata.model,
              let entry = ifd0[TIFFTag.model]
        else { return }
        try patchASCIIRelocate(entry: entry, text: model)
    }

    private mutating func patchGeometry(sourceMetadata: LeicaSourceMetadata) throws {
        if let stripOffsets = ifd0[TIFFTag.stripOffsets] {
            header.patchLongInline(stripOffsets, value: UInt32(layout.previewOffset))
        }
        if let stripByteCounts = ifd0[TIFFTag.stripByteCounts] {
            header.patchLongInline(stripByteCounts, value: UInt32(layout.previewSlot))
        }
        if let orientation = sourceMetadata.orientation, let entry = ifd0[TIFFTag.orientation] {
            header.patchShortInline(entry, value: UInt16(orientation))
        }

        if let entry = rawIFD[TIFFTag.imageWidth] {
            try header.patchScalarInline(entry, value: UInt32(geometry.fullSize.width))
        }
        if let entry = rawIFD[TIFFTag.imageHeight] {
            try header.patchScalarInline(entry, value: UInt32(geometry.fullSize.height))
        }
        if let entry = rawIFD[TIFFTag.stripOffsets] {
            try header.patchScalarInline(entry, value: UInt32(layout.rawOffset))
        }
        if let entry = rawIFD[TIFFTag.rowsPerStrip] {
            try header.patchScalarInline(entry, value: UInt32(geometry.fullSize.height))
        }
        if let entry = rawIFD[TIFFTag.stripByteCounts] {
            try header.patchScalarInline(entry, value: UInt32(layout.rawLength))
        }
        if let entry = rawIFD[TIFFTag.defaultCropOrigin] {
            var raw = Data()
            raw.appendLE(UInt16(geometry.cropOrigin.x))
            raw.appendLE(UInt16(geometry.cropOrigin.y))
            try header.patchEntryPayload(entry, raw: raw)
        }
        if let entry = rawIFD[TIFFTag.defaultCropSize] {
            var raw = Data()
            raw.appendLE(UInt16(geometry.cropSize.width))
            raw.appendLE(UInt16(geometry.cropSize.height))
            try header.patchEntryPayload(entry, raw: raw)
        }
        if let entry = rawIFD[TIFFTag.maskedAreas] {
            try header.patchEntryPayload(entry, raw: maskedAreasPayload())
        }
    }

    private mutating func patchDateTime(sourceMetadata: LeicaSourceMetadata) throws {
        guard let modifyDate = sourceMetadata.modifyDate, let entry = ifd0[TIFFTag.dateTime] else {
            return
        }
        try header.patchASCII(entry, text: modifyDate)
    }

    private mutating func patchExif(sourceMetadata: LeicaSourceMetadata) throws {
        if let exposureTime = sourceMetadata.exposureTime, let entry = exifIFD[TIFFTag.exposureTime] {
            let rational = floatToRational(exposureTime, denominator: 1_000_000)
            header.patchRational(entry, numerator: rational.0, denominator: rational.1)
        }
        if let fNumber = sourceMetadata.fNumber, let entry = exifIFD[TIFFTag.fNumber] {
            let rational = floatToRational(fNumber, denominator: 10_000)
            header.patchRational(entry, numerator: rational.0, denominator: rational.1)
        }
        if let exposureProgram = sourceMetadata.exposureProgram, let entry = exifIFD[TIFFTag.exposureProgram] {
            header.patchShortInline(entry, value: UInt16(exposureProgram))
        }
        if let iso = sourceMetadata.iso, let entry = exifIFD[TIFFTag.iso] {
            header.patchShortInline(entry, value: UInt16(iso))
        }
        if let dateTimeOriginal = sourceMetadata.dateTimeOriginal, let entry = exifIFD[TIFFTag.dateTimeOriginal] {
            try header.patchASCII(entry, text: dateTimeOriginal)
        }
        if let exposureBias = sourceMetadata.exposureCompensation, let entry = exifIFD[TIFFTag.exposureBias] {
            let rational = floatToRational(exposureBias, denominator: 10_000)
            header.patchRational(entry, numerator: rational.0, denominator: rational.1, signed: true)
        }
        if let maxAperture = sourceMetadata.maxApertureValue, let entry = exifIFD[TIFFTag.maxAperture] {
            let rational = floatToRational(maxAperture, denominator: 10_000)
            header.patchRational(entry, numerator: rational.0, denominator: rational.1)
        }
        if let meteringMode = sourceMetadata.meteringMode, let entry = exifIFD[TIFFTag.meteringMode] {
            header.patchShortInline(entry, value: UInt16(meteringMode))
        }
        if let flash = sourceMetadata.flash, let entry = exifIFD[TIFFTag.flash] {
            header.patchShortInline(entry, value: UInt16(flash))
        }
        if let focalLength = sourceMetadata.focalLength, let entry = exifIFD[TIFFTag.focalLength] {
            let rational = floatToRational(focalLength, denominator: 1000)
            header.patchRational(entry, numerator: rational.0, denominator: rational.1)
        }
        if let focalLength35 = sourceMetadata.focalLengthIn35mmFormat, let entry = exifIFD[TIFFTag.focalLength35MM] {
            header.patchShortInline(entry, value: UInt16(focalLength35))
        }
        if let entry = exifIFD[TIFFTag.imageUniqueID] {
            try header.patchASCII(entry, text: UUID().uuidString.replacingOccurrences(of: "-", with: "").uppercased())
        }
    }

    private mutating func patchWhiteBalance() throws {
        guard
            let sourceEntry = sourceIFD0[TIFFTag.asShotNeutral],
            let donorEntry = ifd0[TIFFTag.asShotNeutral]
        else { return }
        try header.patchEntryPayload(donorEntry, raw: try source.payloadBytes(for: sourceEntry))
    }

    private mutating func patchLensIdentity(sourceMetadata: LeicaSourceMetadata) throws {
        if let lensMake = sourceMetadata.lensMake, let entry = exifIFD[TIFFTag.lensMake] {
            try patchASCIIRelocate(entry: entry, text: lensMake)
        }
        if let lensModel = sourceMetadata.lensModel, let entry = exifIFD[TIFFTag.lensModel] {
            try patchASCIIRelocate(entry: entry, text: lensModel)
        }
    }

    private mutating func rewriteRawIFD() throws {
        var additions: [(tag: UInt16, type: UInt16, count: UInt32, payload: Data)] = []

        for tag in [TIFFTag.cfaRepeatPatternDim, TIFFTag.cfaPattern, TIFFTag.activeArea] {
            guard let entry = sourceRawIFD[tag] else { continue }
            var payload = try source.payloadBytes(for: entry)
            if tag == TIFFTag.cfaPattern {
                payload = Self.outputCFARGGBBytes
            } else if tag == TIFFTag.activeArea {
                var raw = Data()
                raw.appendLE(0)
                raw.appendLE(0)
                raw.appendLE(UInt16(geometry.activeSize.height))
                raw.appendLE(UInt16(geometry.activeSize.width))
                payload = raw
            }
            additions.append((tag, entry.type, entry.count, payload))
        }

        for tag in [TIFFTag.opcodeList1, TIFFTag.opcodeList3] {
            guard let entry = sourceRawIFD[tag] else { continue }
            additions.append((tag, entry.type, entry.count, try source.payloadBytes(for: entry)))
        }

        guard !additions.isEmpty else { return }

        struct MutableIFDEntry {
            let tag: UInt16
            let type: UInt16
            let count: UInt32
            let payload: Data
        }

        var entries = rawIFD.values.map {
            MutableIFDEntry(tag: $0.tag, type: $0.type, count: $0.count, payload: header.entryPayload($0))
        }
        for addition in additions {
            entries.removeAll { $0.tag == addition.tag }
            entries.append(MutableIFDEntry(tag: addition.tag, type: addition.type, count: addition.count, payload: addition.payload))
        }
        entries.sort { $0.tag < $1.tag }

        let ifdOffset = alignUp(nextFree, alignment: 2)
        let ifdSize = 2 + entries.count * 12 + 4
        var cursor = ifdOffset + ifdSize
        guard cursor <= layout.rawOffset else {
            throw TIFFError.headerSpaceExhausted(requested: ifdSize, limit: layout.rawOffset)
        }

        var countLE = UInt16(entries.count).littleEndian
        header.replaceBytes(at: ifdOffset, with: Data(bytes: &countLE, count: 2))
        var entryCursor = ifdOffset + 2
        for entry in entries {
            let size = TIFFType.size(of: entry.type, count: entry.count)
            guard entry.payload.count == size else {
                throw HeaderBuildError.payloadMismatch(tag: entry.tag)
            }
            var raw = Data()
            var tag = entry.tag.littleEndian
            var type = entry.type.littleEndian
            var count = entry.count.littleEndian
            raw.append(Data(bytes: &tag, count: 2))
            raw.append(Data(bytes: &type, count: 2))
            raw.append(Data(bytes: &count, count: 4))
            if size <= 4 {
                var inline = entry.payload
                if inline.count < 4 {
                    inline.append(Data(repeating: 0, count: 4 - inline.count))
                }
                raw.append(inline.prefix(4))
            } else {
                let payloadOffset = try header.allocateHeaderBytes(
                    nextFreeOffset: alignUp(cursor, alignment: 2),
                    limitOffset: layout.rawOffset,
                    raw: entry.payload
                )
                cursor = payloadOffset + size
                var value = UInt32(payloadOffset).littleEndian
                raw.append(Data(bytes: &value, count: 4))
            }
            header.replaceBytes(at: entryCursor, with: raw)
            entryCursor += 12
        }
        var nextIFD: UInt32 = 0
        header.replaceBytes(at: entryCursor, with: Data(bytes: &nextIFD, count: 4))
        if let subIFDsEntry = ifd0[TIFFTag.subIFDs] {
            var value = UInt32(ifdOffset).littleEndian
            try header.patchEntryPayload(subIFDsEntry, raw: Data(bytes: &value, count: 4))
        }
        nextFree = cursor
    }

    private mutating func patchMakerNote() throws {
        guard let makerNote = exifIFD[TIFFTag.makerNote] else { return }
        let mnStart = Int(makerNote.value)
        let limit = layout.rawOffset
        guard let countValue = donor.u16(at: mnStart) else {
            throw HeaderBuildError.invalidMakerNote
        }
        let count = Int(countValue)

        for index in 0..<count {
            let entryOffset = mnStart + 2 + index * 12
            guard
                let tag = donor.u16(at: entryOffset),
                let tagType = donor.u16(at: entryOffset + 2),
                let itemCountRaw = donor.u32(at: entryOffset + 4),
                let valueRaw = donor.u32(at: entryOffset + 8)
            else {
                throw HeaderBuildError.invalidMakerNote
            }
            let itemCount = Int(itemCountRaw)
            let value = Int(valueRaw)
            if [HasselbladMakerNoteTag.serial1, HasselbladMakerNoteTag.serial2].contains(tag),
               tagType == TIFFType.ascii,
               value >= 0, value + itemCount <= limit {
                header.zeroRegion(start: value, length: itemCount)
            }
        }

        var cropPayload = Data()
        cropPayload.appendLE(1)
        cropPayload.appendLE(UInt16(geometry.cropOrigin.x))
        cropPayload.appendLE(UInt16(geometry.cropOrigin.y))
        cropPayload.appendLE(UInt16(geometry.cropSize.width))
        cropPayload.appendLE(UInt16(geometry.cropSize.height))
        try patchMakerNoteTag(HasselbladMakerNoteTag.cropInfo, raw: cropPayload)
        header.rewriteIFDWithoutTags(at: mnStart, dropTags: Self.dropMakerNoteTags)
    }

    private mutating func patchMakerNoteTag(_ tag: UInt16, raw: Data) throws {
        guard let makerNote = exifIFD[TIFFTag.makerNote] else { return }
        let mnStart = Int(makerNote.value)
        guard let countValue = donor.u16(at: mnStart) else {
            throw HeaderBuildError.invalidMakerNote
        }
        let count = Int(countValue)
        for index in 0..<count {
            let entryOffset = mnStart + 2 + index * 12
            guard
                let entryTag = donor.u16(at: entryOffset),
                let tagType = donor.u16(at: entryOffset + 2),
                let itemCount = donor.u32(at: entryOffset + 4),
                let value = donor.u32(at: entryOffset + 8)
            else {
                throw HeaderBuildError.invalidMakerNote
            }
            guard entryTag == tag else { continue }
            let size = TIFFType.size(of: tagType, count: itemCount)
            guard raw.count == size else {
                throw HeaderBuildError.payloadMismatch(tag: tag)
            }
            if size <= 4 {
                header.replaceBytes(at: entryOffset + 8, with: raw)
            } else {
                header.replaceBytes(at: Int(value), with: raw)
            }
            return
        }
    }

    private mutating func patchXMP() throws {
        guard let xmpEntry = ifd0[TIFFTag.xmp] else { return }
        let newXMP = Data("""
<x:xmpmeta xmlns:x='adobe:ns:meta/'><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><rdf:Description rdf:about="" xmlns:xap="http://ns.adobe.com/xap/1.0/" xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"><xap:Rating>0</xap:Rating><crs:AutoLateralCA>1</crs:AutoLateralCA></rdf:Description></rdf:RDF></x:xmpmeta>
""".utf8)
        let xmpStart = try header.allocateHeaderBytes(nextFreeOffset: nextFree, limitOffset: layout.rawOffset, raw: newXMP)
        var count = UInt32(newXMP.count).littleEndian
        var offset = UInt32(xmpStart).littleEndian
        header.replaceBytes(at: xmpEntry.entryOffset + 4, with: Data(bytes: &count, count: 4))
        header.replaceBytes(at: xmpEntry.entryOffset + 8, with: Data(bytes: &offset, count: 4))
        nextFree = xmpStart + newXMP.count
    }

    private func maskedAreasPayload() -> Data {
        let fullW = geometry.fullSize.width
        let fullH = geometry.fullSize.height
        let cropX = geometry.cropOrigin.x
        let cropY = geometry.cropOrigin.y
        let cropW = geometry.cropSize.width
        let cropH = geometry.cropSize.height
        let values: [UInt16] = [
            0, 0, UInt16(cropY), UInt16(fullW),
            UInt16(cropY), 0, UInt16(cropY + cropH), UInt16(cropX),
            UInt16(cropY + cropH), 0, UInt16(fullH), UInt16(fullW),
            UInt16(cropY), UInt16(cropX + cropW), UInt16(cropY + cropH), UInt16(fullW),
        ]
        var raw = Data()
        values.forEach { raw.appendLE($0) }
        return raw
    }

    private mutating func patchASCIIRelocate(entry: TIFFEntry, text: String) throws {
        let encoded = (text.data(using: .ascii, allowLossyConversion: true) ?? Data()) + Data([0])
        if encoded.count <= Int(entry.count) {
            try header.patchASCII(entry, text: text)
            return
        }
        let start = try header.allocateHeaderBytes(nextFreeOffset: nextFree, limitOffset: layout.rawOffset, raw: encoded)
        var count = UInt32(encoded.count).littleEndian
        var offset = UInt32(start).littleEndian
        header.replaceBytes(at: entry.entryOffset + 4, with: Data(bytes: &count, count: 4))
        header.replaceBytes(at: entry.entryOffset + 8, with: Data(bytes: &offset, count: 4))
        nextFree = start + encoded.count
    }

    private func floatToRational(_ value: Double, denominator: Int32) -> (Int32, Int32) {
        let numerator = Int32((value * Double(denominator)).rounded())
        let divisor = gcd(abs(numerator), denominator)
        return (numerator / divisor, denominator / divisor)
    }

    private func gcd(_ a: Int32, _ b: Int32) -> Int32 {
        var x = a
        var y = b
        while y != 0 {
            let r = x % y
            x = y
            y = r
        }
        return x == 0 ? 1 : x
    }

    private func alignUp(_ value: Int, alignment: Int) -> Int {
        ((value + alignment - 1) / alignment) * alignment
    }
}
