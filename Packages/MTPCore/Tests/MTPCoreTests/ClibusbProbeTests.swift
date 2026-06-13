import XCTest
@testable import MTPCore

final class ClibusbProbeTests: XCTestCase {
    /// 验证 modulemap 配置正确:import Clibusb 能编译 + libusb_get_version 符号链接成功。
    /// libusb_get_version 返回编译期版本(无需 libusb_init),是最轻量的 import 探针。
    func testLibusbVersionProbeReturnsRealVersion() throws {
        let version = _libusbVersionProbe()
        XCTAssertFalse(version.isEmpty, "libusb_get_version 不应返回空")
        XCTAssertNotEqual(version, "unknown", "应拿到真实版本号(如 1.0.30),而非 unknown")
        // 打印便于人工核对(应匹配 brew install libusb 的版本)
        print("libusb 版本: \(version)")
    }
}
