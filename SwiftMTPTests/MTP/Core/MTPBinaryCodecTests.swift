import XCTest
@testable import SwiftMTP

final class MTPBinaryCodecTests: XCTestCase {
    func testWriterEmitsLittleEndianIntegersAndMTPStrings() throws {
        var writer = MTPBinaryWriter()
        writer.write(UInt8(0x12))
        writer.write(UInt16(0x3456))
        writer.write(UInt32(0x789A_BCDE))
        writer.write(UInt64(0x0123_4567_89AB_CDEF))
        try writer.writeMTPString("A")
        try writer.writeMTPString("")

        XCTAssertEqual(
            writer.data,
            Data([
                0x12,
                0x56, 0x34,
                0xDE, 0xBC, 0x9A, 0x78,
                0xEF, 0xCD, 0xAB, 0x89, 0x67, 0x45, 0x23, 0x01,
                0x02, 0x41, 0x00, 0x00, 0x00,
                0x00,
            ])
        )
    }

    func testReaderDecodesValuesAndTracksCursor() throws {
        var reader = MTPBinaryReader(
            data: Data([
                0x12,
                0x56, 0x34,
                0xDE, 0xBC, 0x9A, 0x78,
                0xEF, 0xCD, 0xAB, 0x89, 0x67, 0x45, 0x23, 0x01,
                0x02, 0x41, 0x00, 0x00, 0x00,
                0x00,
            ])
        )

        XCTAssertEqual(try reader.readUInt8(), 0x12)
        XCTAssertEqual(try reader.readUInt16(), 0x3456)
        XCTAssertEqual(try reader.readUInt32(), 0x789A_BCDE)
        XCTAssertEqual(try reader.readUInt64(), 0x0123_4567_89AB_CDEF)
        XCTAssertEqual(try reader.readMTPString(), "A")
        XCTAssertEqual(try reader.readMTPString(), "")
        XCTAssertEqual(reader.remainingCount, 0)
    }

    func testReaderRejectsTruncatedAndMalformedStringsWithoutAdvancingPastBounds() {
        var shortReader = MTPBinaryReader(data: Data([0x01, 0x02, 0x03]))
        XCTAssertThrowsError(try shortReader.readUInt32())
        XCTAssertEqual(shortReader.offset, 0)

        var unterminated = MTPBinaryReader(data: Data([0x02, 0x41, 0x00, 0x42, 0x00]))
        XCTAssertThrowsError(try unterminated.readMTPString())
        XCTAssertEqual(unterminated.offset, 0)

        var truncated = MTPBinaryReader(data: Data([0x02, 0x41, 0x00]))
        XCTAssertThrowsError(try truncated.readMTPString())
        XCTAssertEqual(truncated.offset, 0)
    }

    func testWriterRejectsEmbeddedNullAndOverlongString() {
        var embeddedNull = MTPBinaryWriter()
        XCTAssertThrowsError(try embeddedNull.writeMTPString("A\0B"))
        XCTAssertTrue(embeddedNull.data.isEmpty)

        var overlong = MTPBinaryWriter()
        XCTAssertThrowsError(try overlong.writeMTPString(String(repeating: "A", count: 255)))
        XCTAssertTrue(overlong.data.isEmpty)
    }

    func testReaderTreatsOffsetsAsRelativeToANonZeroDataSlice() throws {
        let source = Data([0xFF, 0x44, 0x33, 0x22, 0x11])
        var reader = MTPBinaryReader(data: source.dropFirst())

        XCTAssertEqual(try reader.readUInt32(), 0x1122_3344)
        XCTAssertEqual(reader.remainingCount, 0)
    }
}
