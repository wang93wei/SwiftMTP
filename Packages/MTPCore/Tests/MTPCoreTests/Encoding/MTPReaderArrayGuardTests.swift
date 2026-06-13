import XCTest
@testable import MTPCore

/// M-4 count 上限保护测试(Plan 1 final review M-4)。
/// 防恶意设备回巨量 count → 巨量内存分配。readU32Array/readU16Array 双重校验:
///   1. count <= MTPReadPolicy.maxArrayElementCount(全局上限)
///   2. count*sizeof <= remaining(声明不超出实际字节)
final class MTPReaderArrayGuardTests: XCTestCase {

    // MARK: readU32Array

    /// 正常 count(在上限内,正好等于 remaining/4)。基线不回归。
    func testReadU32ArrayNormal() throws {
        // count=2,后跟 8 字节(2×u32,小端)
        let bytes: [UInt8] = [2, 0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0]
        var reader = MTPReader(bytes)
        XCTAssertEqual(try reader.readU32Array(), [1, 2])
    }

    /// M-4:count 超全局上限(0xFFFFFFFF >> maxArrayElementCount)→ 拒绝。
    func testReadU32ArrayExceedsMaxCount() {
        let bytes: [UInt8] = [0xFF, 0xFF, 0xFF, 0xFF]
        var reader = MTPReader(bytes)
        // 区分于 endOfData:M-4 是声明超全局上限 → arrayTooLarge(携带 count)。
        XCTAssertThrowsError(try reader.readU32Array()) { error in
            guard case .arrayTooLarge(let count) = error as? MTPDecodeError else {
                XCTFail("期望 arrayTooLarge,得到 \(error)"); return
            }
            XCTAssertEqual(count, 0xFFFFFFFF)
        }
    }

    /// M-4:count 在上限内但声明 > remaining/4(超出实际字节)→ 拒绝。
    /// 这种应抛 endOfData(逐字节读时 _read 越界),非 arrayTooLarge。
    func testReadU32ArrayDeclaredExceedsRemaining() {
        // count=10(上限内),但后无数据
        let bytes: [UInt8] = [10, 0, 0, 0]
        var reader = MTPReader(bytes)
        XCTAssertThrowsError(try reader.readU32Array())
    }

    // MARK: readU16Array

    /// 正常 count。基线不回归。
    func testReadU16ArrayNormal() throws {
        // count=1,后跟 2 字节(1×u16,小端 0x0130)
        let bytes: [UInt8] = [1, 0, 0, 0, 0x30, 0x01]
        var reader = MTPReader(bytes)
        XCTAssertEqual(try reader.readU16Array(), [0x0130])
    }

    /// M-4:count 超全局上限 → 拒绝。
    func testReadU16ArrayExceedsMaxCount() {
        let bytes: [UInt8] = [0xFF, 0xFF, 0xFF, 0xFF]
        var reader = MTPReader(bytes)
        XCTAssertThrowsError(try reader.readU16Array()) { error in
            guard case .arrayTooLarge(let count) = error as? MTPDecodeError else {
                XCTFail("期望 arrayTooLarge,得到 \(error)"); return
            }
            XCTAssertEqual(count, 0xFFFFFFFF)
        }
    }

    // MARK: count==0 边界(此前未覆盖)
    // count==0 应返回空数组,且只消耗 4 字节长度前缀,不读任何后续字节。

    func testReadU32ArrayZeroCount() throws {
        // count=0,后跟未消费字节(验证 count==0 不越界读取)
        let bytes: [UInt8] = [0, 0, 0, 0, 0xFF, 0xFF]
        var reader = MTPReader(bytes)
        XCTAssertEqual(try reader.readU32Array(), [])
        XCTAssertEqual(reader.remaining, 2, "count==0 应只消耗 4 字节长度前缀")
    }

    func testReadU16ArrayZeroCount() throws {
        // count=0,后跟未消费字节
        let bytes: [UInt8] = [0, 0, 0, 0, 0xAA, 0xBB]
        var reader = MTPReader(bytes)
        XCTAssertEqual(try reader.readU16Array(), [])
        XCTAssertEqual(reader.remaining, 2, "count==0 应只消耗 4 字节长度前缀")
    }
}
