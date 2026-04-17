import Foundation

struct CameraMapping: Identifiable, Hashable {
    let id: String
    let label: String
    let sourceExtensions: [String]      // ex ["3FR", "FFF"]
    let targetMake: String
    let targetModel: String
    let targetUniqueCameraModel: String

    static let all: [CameraMapping] = [
        CameraMapping(
            id: "hassy-x2d2-to-fuji-gfx100s2",
            label: "Hasselblad X2D II → Fuji GFX 100S II",
            sourceExtensions: ["3FR", "FFF"],
            targetMake: "FUJIFILM",
            targetModel: "GFX 100S II",
            targetUniqueCameraModel: "Fujifilm GFX 100S II"
        ),
        // Futurs mappings :
        // .init(id: "ricoh-griii-to-fuji-xh2s", label: "Ricoh GR III → Fuji X-H2S", ...)
        // .init(id: "leica-q3-to-fuji-gfx100ii", label: "Leica Q3 → Fuji GFX 100 II", ...)
    ]

    static var `default`: CameraMapping { all[0] }
}
