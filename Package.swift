// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SongHarmonize",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SongHarmonize", targets: ["SongHarmonize"])
    ],
    targets: [
        .executableTarget(
            name: "SongHarmonize",
            resources: [.process("Resources")]
        ),
        .testTarget(name: "SongHarmonizeTests", dependencies: ["SongHarmonize"])
    ]
)
