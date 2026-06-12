// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MTPCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MTPCore", targets: ["MTPCore"]),
    ],
    targets: [
        .target(
            name: "MTPCore",
            path: "Sources/MTPCore"
        ),
        .testTarget(
            name: "MTPCoreTests",
            dependencies: ["MTPCore"],
            path: "Tests/MTPCoreTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
