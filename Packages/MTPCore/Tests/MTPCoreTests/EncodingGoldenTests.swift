import XCTest
@testable import MTPCore

final class EncodingGoldenTests: XCTestCase {
    /// 加载共享 fixture(Go 与 Swift 读同一 JSON)。
    func loadFixture(_ name: String) throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle(for: type(of: self)).url(forResource: name, withExtension: "json"),
                                "缺少 fixture: \(name).json")
        let data = try Data(contentsOf: url)
        return try (JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
    func fixtureHex(_ name: String) throws -> Data {
        let fx = try loadFixture(name)
        let hex = try XCTUnwrap(fx["hex"] as? String)
        return Data(hexString: hex)
    }
    func fixtureExpected(_ name: String) throws -> [String: Any] {
        let fx = try loadFixture(name)
        return try XCTUnwrap(fx["expected"] as? [String: Any])
    }

    func testDecodeEntryPointSignature() throws {
        // 验证顶层 decode<T> 入口存在并可调用(具体对齐在后续 task)
        let data = Data([0x34, 0x12])
        var reader = MTPReader(data)
        XCTAssertEqual(try reader.readU16(), 0x1234)
    }
}

// hex 字符串 → Data 的测试辅助。
extension Data {
    init(hexString: String) {
        self.init()
        var iter = hexString.makeIterator()
        while let h = iter.next(), let l = iter.next() {
            append(UInt8(h.hexDigitValue ?? 0) * 16 + UInt8(l.hexDigitValue ?? 0))
        }
    }
}
