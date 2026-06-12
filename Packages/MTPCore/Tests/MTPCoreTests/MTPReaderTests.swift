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
}
