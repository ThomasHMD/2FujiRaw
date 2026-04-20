import Foundation

struct LeicaSourceMetadata {
    let make: String?
    let model: String?
    let uniqueCameraModel: String?
    let serialNumber: String?
    let bodySerialNumber: String?
    let cameraSerialNumber: String?
    let orientation: Int?
    let modifyDate: String?
    let exposureTime: Double?
    let fNumber: Double?
    let exposureProgram: Int?
    let iso: Int?
    let dateTimeOriginal: String?
    let exposureCompensation: Double?
    let maxApertureValue: Double?
    let meteringMode: Int?
    let flash: Int?
    let focalLength: Double?
    let focalLengthIn35mmFormat: Int?
    let lensMake: String?
    let lensModel: String?
}

enum LeicaSourceMetadataExtractor {
    static func extract(from sourceURL: URL, exiftoolURL: URL) throws -> LeicaSourceMetadata {
        let tags = [
            "Make",
            "Model",
            "UniqueCameraModel",
            "SerialNumber",
            "BodySerialNumber",
            "CameraSerialNumber",
            "Orientation",
            "ModifyDate",
            "ExposureTime",
            "FNumber",
            "ExposureProgram",
            "ISO",
            "DateTimeOriginal",
            "ExposureCompensation",
            "MaxApertureValue",
            "MeteringMode",
            "Flash",
            "FocalLength",
            "FocalLengthIn35mmFormat",
            "LensMake",
            "LensModel",
        ]

        let result = try ProcessRunner.run(
            executableURL: exiftoolURL,
            arguments: ["-j", "-n"] + tags.map { "-\($0)" } + [sourceURL.path]
        )
        let out = result.stdout
        let err = result.stderr
        guard result.exitCode == 0 else {
            let message = String(data: err.isEmpty ? out : err, encoding: .utf8) ?? "exiftool failed"
            throw NSError(domain: "LeicaSourceMetadataExtractor", code: Int(result.exitCode), userInfo: [
                NSLocalizedDescriptionKey: message
            ])
        }

        let json = try JSONSerialization.jsonObject(with: out) as? [[String: Any]]
        let payload = json?.first ?? [:]

        func intValue(_ key: String) -> Int? {
            if let n = payload[key] as? NSNumber { return n.intValue }
            if let s = payload[key] as? String { return Int(s) }
            return nil
        }

        func doubleValue(_ key: String) -> Double? {
            if let n = payload[key] as? NSNumber { return n.doubleValue }
            if let s = payload[key] as? String { return Double(s) }
            return nil
        }

        func stringValue(_ key: String) -> String? {
            if let s = payload[key] as? String, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return s
            }
            return nil
        }

        return LeicaSourceMetadata(
            make: stringValue("Make"),
            model: stringValue("Model"),
            uniqueCameraModel: stringValue("UniqueCameraModel"),
            serialNumber: stringValue("SerialNumber"),
            bodySerialNumber: stringValue("BodySerialNumber"),
            cameraSerialNumber: stringValue("CameraSerialNumber"),
            orientation: intValue("Orientation"),
            modifyDate: stringValue("ModifyDate"),
            exposureTime: doubleValue("ExposureTime"),
            fNumber: doubleValue("FNumber"),
            exposureProgram: intValue("ExposureProgram"),
            iso: intValue("ISO"),
            dateTimeOriginal: stringValue("DateTimeOriginal"),
            exposureCompensation: doubleValue("ExposureCompensation"),
            maxApertureValue: doubleValue("MaxApertureValue"),
            meteringMode: intValue("MeteringMode"),
            flash: intValue("Flash"),
            focalLength: doubleValue("FocalLength"),
            focalLengthIn35mmFormat: intValue("FocalLengthIn35mmFormat"),
            lensMake: stringValue("LensMake"),
            lensModel: stringValue("LensModel")
        )
    }
}
