// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MTPCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MTPCore", targets: ["MTPCore"]),
    ],
    targets: [
        // libusb 系统库 wrapper:modulemap 声明绝对路径 header + link "usb-1.0"。
        // pkgConfig 让 SwiftPM 用 pkg-config 自动发现 -L(libusb-1.0.pc 随 brew 安装),
        // 替代 unsafeFlags(unsafeFlags 在作为远程依赖发布时会被 SwiftPM 拒绝)。
        .systemLibrary(
            name: "Clibusb",
            path: "Sources/Clibusb",
            pkgConfig: "libusb-1.0",
            providers: [.brew(["libusb"])]
        ),
        .target(
            name: "MTPCore",
            dependencies: ["Clibusb"],
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
