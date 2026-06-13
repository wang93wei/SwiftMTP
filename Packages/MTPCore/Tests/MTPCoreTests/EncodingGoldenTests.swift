import XCTest
@testable import MTPCore

final class EncodingGoldenTests: XCTestCase {
    /// 加载共享 fixture(Go 与 Swift 读同一 JSON)。
    /// 资源由 `.copy("Fixtures")` 打进 SwiftPM 生成的资源 bundle
    /// (`MTPCore_MTPCoreTests.bundle`),用 `Bundle.module` 定位,
    /// 而非 `Bundle(for:)`(后者拿到的是 xctest 容器,查不到嵌套资源)。
    /// `.copy` 保留目录结构,故资源在 `Fixtures/` 子目录下,需传 `subdirectory`。
    func loadFixture(_ name: String) throws -> [String: Any] {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
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

    // MARK: - Task 8: ObjectInfo 对齐 Go 黄金 fixture

    func testDecodeObjectInfoSimpleAlignsWithGo() throws {
        let data = try fixtureHex("objectinfo_simple")
        let info = try decode(data, as: ObjectInfo.self)
        let exp = try fixtureExpected("objectinfo_simple")
        XCTAssertEqual(info.storageID, uint32(exp["storageID"]))
        XCTAssertEqual(info.objectFormat, uint16(exp["objectFormat"]))
        XCTAssertEqual(info.compressedSize, uint32(exp["compressedSize"]))
        XCTAssertEqual(info.parentObject, uint32(exp["parentObject"]))
        XCTAssertEqual(info.filename, exp["filename"] as? String)
        XCTAssertNil(info.captureDate, "simple fixture 无时间")
        XCTAssertNil(info.modificationDate)
    }

    func testDecodeObjectInfoCJKAlignsWithGo() throws {
        let data = try fixtureHex("objectinfo_cjk")
        let info = try decode(data, as: ObjectInfo.self)
        let exp = try fixtureExpected("objectinfo_cjk")
        XCTAssertEqual(info.filename, exp["filename"] as? String, "CJK 文件名应一致")
        XCTAssertEqual(info.compressedSize, uint32(exp["compressedSize"]))
        let modUnix = try XCTUnwrap(exp["modificationTime"] as? Double)
        XCTAssertEqual(info.modificationDate!.timeIntervalSince1970, modUnix, accuracy: 1.0)
    }

    // MARK: - Task 9: StorageInfo + Uint32Array 对齐 Go 黄金 fixture

    func testDecodeStorageInfoAlignsWithGo() throws {
        let data = try fixtureHex("storageinfo_simple")
        let st = try decode(data, as: StorageInfo.self)
        let exp = try fixtureExpected("storageinfo_simple")
        XCTAssertEqual(st.storageType, uint16(exp["storageType"]))
        XCTAssertEqual(st.filesystemType, uint16(exp["filesystemType"]))
        XCTAssertEqual(st.maxCapability, uint64(exp["maxCapability"]))
        XCTAssertEqual(st.freeSpaceInBytes, uint64(exp["freeSpaceInBytes"]))
        XCTAssertEqual(st.storageDescription, exp["storageDescription"] as? String)
        XCTAssertEqual(st.volumeLabel, exp["volumeLabel"] as? String)
    }

    func testDecodeUint32ArrayAlignsWithGo() throws {
        let data = try fixtureHex("uint32array_simple")
        let arr = try decode(data, as: Uint32Array.self)
        let exp = try fixtureExpected("uint32array_simple")
        let expVals = (exp["values"] as? [NSNumber])?.map { $0.uint32Value } ?? []
        XCTAssertEqual(arr.values, expVals)
    }
}

// JSON 数字转 UInt 辅助(JSONSerialization 把数字给成 NSNumber)。
private func uint32(_ v: Any?) -> UInt32 { (v as? NSNumber)?.uint32Value ?? 0 }
private func uint16(_ v: Any?) -> UInt16 { (v as? NSNumber)?.uint16Value ?? 0 }
private func uint64(_ v: Any?) -> UInt64 { (v as? NSNumber)?.uint64Value ?? 0 }

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
