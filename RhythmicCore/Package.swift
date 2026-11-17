// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RhythmicCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "RhythmicCore", targets: ["RhythmicCore"]),
    ],
    targets: [
        .target(name: "RhythmicCore", resources: [.copy("Resources/airports.tsv"), .copy("Resources/AIRPORTS-LICENSE.txt")]),
        .executableTarget(name: "rhythmic-cli", dependencies: ["RhythmicCore"]),
        .testTarget(name: "RhythmicCoreTests", dependencies: ["RhythmicCore"]),
    ]
)
