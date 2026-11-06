import Foundation

enum TIFFTag {
    static let make: UInt16 = 0x010F
    static let model: UInt16 = 0x0110
    static let subIFDs: UInt16 = 0x014A
    static let imageWidth: UInt16 = 0x0100
    static let imageHeight: UInt16 = 0x0101
    static let stripOffsets: UInt16 = 0x0111
    static let orientation: UInt16 = 0x0112
    static let rowsPerStrip: UInt16 = 0x0116
    static let stripByteCounts: UInt16 = 0x0117
    static let dateTime: UInt16 = 0x0132
    static let xmp: UInt16 = 0x02BC
    static let exifIFD: UInt16 = 0x8769

    static let cfaRepeatPatternDim: UInt16 = 0x828D
    static let cfaPattern: UInt16 = 0x828E
    static let blackLevel: UInt16 = 0xC61A
    static let whiteLevel: UInt16 = 0xC61D
    static let defaultCropOrigin: UInt16 = 0xC61F
    static let defaultCropSize: UInt16 = 0xC620
    static let colorMatrix1: UInt16 = 0xC621
    static let colorMatrix2: UInt16 = 0xC622
    static let asShotNeutral: UInt16 = 0xC628
    static let calibrationIlluminant1: UInt16 = 0xC65A
    static let calibrationIlluminant2: UInt16 = 0xC65B
    static let activeArea: UInt16 = 0xC68D
    static let maskedAreas: UInt16 = 0xC68E
    static let opcodeList1: UInt16 = 0xC740
    static let opcodeList3: UInt16 = 0xC74E

    static let exposureTime: UInt16 = 0x829A
    static let fNumber: UInt16 = 0x829D
    static let exposureProgram: UInt16 = 0x8822
    static let iso: UInt16 = 0x8827
    static let makerNote: UInt16 = 0x927C
    static let dateTimeOriginal: UInt16 = 0x9003
    static let exposureBias: UInt16 = 0x9204
    static let maxAperture: UInt16 = 0x9205
    static let meteringMode: UInt16 = 0x9207
    static let flash: UInt16 = 0x9209
    static let focalLength: UInt16 = 0x920A
    static let focalLength35MM: UInt16 = 0xA405
    static let imageUniqueID: UInt16 = 0xA420
    static let lensMake: UInt16 = 0xA433
    static let lensModel: UInt16 = 0xA434
}

enum HasselbladMakerNoteTag {
    static let lensCode: UInt16 = 0x0045
    static let cropInfo: UInt16 = 0x0059
    static let serial1: UInt16 = 0x0060
    static let serial2: UInt16 = 0x0061
    static let hncsBlocker: UInt16 = 0x0017
}
