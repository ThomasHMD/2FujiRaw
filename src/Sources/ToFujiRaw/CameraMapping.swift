import Foundation

enum ConversionPipeline: String, Hashable {
    case nativeHasselbladToFuji
    case leicaViaHasselbladToFuji
    case nativeLeicaToHasselblad
}

struct CameraMapping: Identifiable, Hashable {
    let id: String
    let label: String
    let sourceExtensions: [String]
    let outputExtension: String
    let outputDirectoryName: String
    let pipeline: ConversionPipeline
    let targetMake: String?
    let targetModel: String?
    let targetUniqueCameraModel: String?
    let requiresDonor: Bool
    let donorLabel: String?

    static let all: [CameraMapping] = [
        CameraMapping(
            id: "hassy-x2d2-to-fuji-gfx100s2",
            label: "Hasselblad X2D II → Fuji GFX 100S II",
            sourceExtensions: ["3FR", "FFF"],
            outputExtension: "dng",
            outputDirectoryName: "DNG-Fuji-Converted",
            pipeline: .nativeHasselbladToFuji,
            targetMake: "FUJIFILM",
            targetModel: "GFX 100S II",
            targetUniqueCameraModel: "Fujifilm GFX 100S II",
            requiresDonor: false,
            donorLabel: nil
        ),
        CameraMapping(
            id: "leica-dng-to-fuji-gfx100s2",
            label: "Leica DNG → Fuji GFX 100S II",
            sourceExtensions: ["DNG"],
            outputExtension: "dng",
            outputDirectoryName: "DNG-Fuji-Converted",
            pipeline: .leicaViaHasselbladToFuji,
            targetMake: "FUJIFILM",
            targetModel: "GFX 100S II",
            targetUniqueCameraModel: "Fujifilm GFX 100S II",
            requiresDonor: true,
            donorLabel: "X2D Template"
        ),
        CameraMapping(
            id: "leica-dng-to-hasselblad-x2d2",
            label: "Leica DNG → Hasselblad X2D",
            sourceExtensions: ["DNG"],
            outputExtension: "3fr",
            outputDirectoryName: "3FR-Hasselblad-Converted",
            pipeline: .nativeLeicaToHasselblad,
            targetMake: nil,
            targetModel: nil,
            targetUniqueCameraModel: nil,
            requiresDonor: true,
            donorLabel: "X2D Template"
        ),
    ]

    static var `default`: CameraMapping { all[0] }

    var hasLeicaSource: Bool {
        switch pipeline {
        case .leicaViaHasselbladToFuji, .nativeLeicaToHasselblad:
            return true
        case .nativeHasselbladToFuji:
            return false
        }
    }
}
