// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MTPCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MTPCore", targets: ["MTPCore"]),
    ],
    targets: [
        // libusb 系统库 wrapper:modulemap 声明 header + link "usb-1.0"。
        // 不加 pkgConfig(避免 pkg-config 缺失构建失败);绝对路径锁定 Homebrew。
        .systemLibrary(
            name: "Clibusb",
            path: "Sources/Clibusb",
            providers: [.brew(["libusb"])]
        ),
        .target(
            name: "MTPCore",
            dependencies: ["Clibusb"],
            path: "Sources/MTPCore",
            // libusb 装在 Homebrew 非标准路径,modulemap 的 `link "usb-1.0"` 找不到库。
            // 用 linkerSettings 显式提供 -L 路径 + -lusb-1.0。绝对路径锁定 Apple Silicon Homebrew。
            linkerSettings: [
                .unsafeFlags(["-L/opt/homebrew/opt/libusb/lib"]),
                .linkedLibrary("usb-1.0"),
            ]
        ),
        .testTarget(
            name: "MTPCoreTests",
            dependencies: ["MTPCore"],
            path: "Tests/MTPCoreTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
