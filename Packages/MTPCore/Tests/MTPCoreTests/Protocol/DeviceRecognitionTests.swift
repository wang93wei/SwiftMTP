import XCTest
@testable import MTPCore

final class DeviceRecognitionTests: XCTestCase {
    // P3:接口串关键词判定(大小写敏感,对齐 Go strings.Contains)
    func testInterfaceStringLooksLikeMTP() {
        XCTAssertTrue(interfaceStringLooksLikeMTP("MTP"))
        XCTAssertTrue(interfaceStringLooksLikeMTP("SAMSUNG CDC ACM"))   // P3 三星
        XCTAssertTrue(interfaceStringLooksLikeMTP("CDC-ACM"))
        XCTAssertFalse(interfaceStringLooksLikeMTP("MassStorage"))
        XCTAssertFalse(interfaceStringLooksLikeMTP(""))
        XCTAssertFalse(interfaceStringLooksLikeMTP("mtp"))  // 小写不命中(对齐 Go 大小写敏感)
    }

    // P4:microsoft/fujifilm 兜底判定(无接口串时)
    func testMTPExtensionFallback() {
        XCTAssertTrue(mtpExtensionFallback("microsoft/WindowsPhone 1.0"))
        XCTAssertTrue(mtpExtensionFallback("fujifilm.co.jp: 1.0;"))
        XCTAssertFalse(mtpExtensionFallback("microsoft.com: 1.0;"))  // 普通 MTP 扩展不算
        XCTAssertFalse(mtpExtensionFallback(""))
    }

    // 设备 ID 正则匹配(对应 select.go:103)
    func testDeviceMatchesPattern() throws {
        XCTAssertTrue(try deviceMatchesPattern("Samsung Galaxy S24", pattern: "Samsung"))
        XCTAssertTrue(try deviceMatchesPattern("any", pattern: ""))   // 空 pattern 恒 true
        XCTAssertFalse(try deviceMatchesPattern("Pixel 8", pattern: "Samsung"))
        XCTAssertThrowsError(try deviceMatchesPattern("x", pattern: "["))  // 无效正则
    }
}
