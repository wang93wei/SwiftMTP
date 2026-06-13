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

    func testReadMTPTimeEmpty() throws {
        // 空字符串(长度0)→ nil(无时间)
        var reader = MTPReader(Data([0x00]))
        XCTAssertNil(try reader.readMTPTime())
    }

    func testReadMTPTimeStandard() throws {
        // "20260613T143000" → 对应 UTC 时间。线序:sz=16(15字符+尾零)... 见 Go encodeStr
        // 构造:codepoints = 15 + 1(尾零) = 16
        let s = "20260613T143000"
        var bytes: [UInt8] = [UInt8(s.count + 1)] // sz 含尾零
        for c in s.unicodeScalars { bytes.append(UInt8(c.value & 0xFF)); bytes.append(UInt8((c.value >> 8) & 0xFF)) }
        bytes.append(0x00); bytes.append(0x00) // 尾零
        var reader = MTPReader(Data(bytes))
        let date = try reader.readMTPTime()
        XCTAssertNotNil(date)
        // 2026-06-13 14:30:00 UTC
        let cal = Calendar(identifier: .gregorian)
        var comps = DateComponents(); comps.timeZone = TimeZone(identifier: "UTC")
        comps.year = 2026; comps.month = 6; comps.day = 13
        comps.hour = 14; comps.minute = 30; comps.second = 0
        let expected = try XCTUnwrap(cal.date(from: comps))
        XCTAssertEqual(date!.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 1.0)
    }

    func testReadMTPTimeSamsungTrailingDot() throws {
        // 三星尾点:"20260613T143000." → 应被 trim 后正确解析
        let s = "20260613T143000."
        var bytes: [UInt8] = [UInt8(s.count + 1)]
        for c in s.unicodeScalars { bytes.append(UInt8(c.value & 0xFF)); bytes.append(UInt8((c.value >> 8) & 0xFF)) }
        bytes.append(0x00); bytes.append(0x00)
        var reader = MTPReader(Data(bytes))
        XCTAssertNotNil(try reader.readMTPTime())
    }

    func testReadMTPTimeJollaTrailingZ() throws {
        // Jolla 尾 Z:"20260613T143000Z" → 应被 trim 后按标准格式解析
        let s = "20260613T143000Z"
        var bytes: [UInt8] = [UInt8(s.count + 1)]
        for c in s.unicodeScalars { bytes.append(UInt8(c.value & 0xFF)); bytes.append(UInt8((c.value >> 8) & 0xFF)) }
        bytes.append(0x00); bytes.append(0x00)
        var reader = MTPReader(Data(bytes))
        XCTAssertNotNil(try reader.readMTPTime(), "Jolla 尾 Z 应可解析")
    }

    func testReadMTPTimeNokiaNumTZ() throws {
        // Nokia 数字时区:"20260613T143000-0700"
        let s = "20260613T143000-0700"
        var bytes: [UInt8] = [UInt8(s.count + 1)]
        for c in s.unicodeScalars { bytes.append(UInt8(c.value & 0xFF)); bytes.append(UInt8((c.value >> 8) & 0xFF)) }
        bytes.append(0x00); bytes.append(0x00)
        var reader = MTPReader(Data(bytes))
        XCTAssertNotNil(try reader.readMTPTime(), "Nokia numTZ 应可解析")
    }

    func testReadMTPTimeInvalidThrows() throws {
        let s = "garbage"
        var bytes: [UInt8] = [UInt8(s.count + 1)]
        for c in s.unicodeScalars { bytes.append(UInt8(c.value & 0xFF)); bytes.append(UInt8((c.value >> 8) & 0xFF)) }
        bytes.append(0x00); bytes.append(0x00)
        var reader = MTPReader(Data(bytes))
        XCTAssertThrowsError(try reader.readMTPTime()) { error in
            guard case MTPDecodeError.invalidTime = error else {
                XCTFail("期望 invalidTime,实际 \(error)"); return
            }
        }
    }
}
