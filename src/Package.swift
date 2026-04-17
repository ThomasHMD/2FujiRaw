// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ToFujiRaw",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ToFujiRaw",
            path: "Sources/ToFujiRaw",
            exclude: ["Resources"]   // Resources gérées au bundling, pas SwiftPM
        )
    ]
)
