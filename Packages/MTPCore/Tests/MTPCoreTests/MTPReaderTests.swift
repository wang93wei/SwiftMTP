import XCTest
@testable import MTPCore

final class MTPReaderTests: XCTestCase {
    func testReadU8() throws {
        var reader = MTPReader(Data([0x01, 0xFF]))
        XCTAssertEqual(try reader.readU8(), 0x01)
        XCTAssertEqual(try reader.readU8(), 0xFF)
    }

    func testReadU16LittleEndian() throws {
        // 0x1234 小端 = 34 12
        var reader = MTPReader(Data([0x34, 0x12]))
        XCTAssertEqual(try reader.readU16(), 0x1234)
    }

    func testReadU32LittleEndian() throws {
        // 0xDEADBEEF 小端 = EF BE AD DE
        var reader = MTPReader(Data([0xEF, 0xBE, 0xAD, 0xDE]))
        XCTAssertEqual(try reader.readU32(), 0xDEADBEEF)
    }

    func testReadU64LittleEndian() throws {
        var reader = MTPReader(Data([0x78, 0x56, 0x34, 0x12, 0x00, 0x00, 0x00, 0x00]))
        XCTAssertEqual(try reader.readU64(), 0x12345678)
    }

    func testReadBeyondEndThrows() throws {
        var reader = MTPReader(Data([0x01]))
        _ = try reader.readU8()
        XCTAssertThrowsError(try reader.readU8()) { error in
            guard case MTPDecodeError.endOfData = error else {
                XCTFail("期望 endOfData,实际 \(error)"); return
            }
        }
    }

    func testIsAtEnd() throws {
        var reader = MTPReader(Data([0x01, 0x02]))
        XCTAssertFalse(reader.isAtEnd)
        _ = try reader.readU16()
        XCTAssertTrue(reader.isAtEnd)
    }

    func testReadMTPStringAscii() throws {
        // "AB" + 尾零:sz=3,然后 'A'=41 00,'B'=42 00,尾零=00 00
        var reader = MTPReader(Data([0x03, 0x41, 0x00, 0x42, 0x00, 0x00, 0x00]))
        XCTAssertEqual(try reader.readMTPString(), "AB")
    }

    func testReadMTPStringEmpty() throws {
        // sz=0 → 空串
        var reader = MTPReader(Data([0x00]))
        XCTAssertEqual(try reader.readMTPString(), "")
    }

    func testReadMTPStringCJK() throws {
        // "中" U+4E2D 小端 = 2D 4E;sz=2(字符+尾零)
        var reader = MTPReader(Data([0x02, 0x2D, 0x4E, 0x00, 0x00]))
        XCTAssertEqual(try reader.readMTPString(), "中")
    }
}
