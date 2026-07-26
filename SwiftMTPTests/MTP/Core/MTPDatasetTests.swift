import XCTest
@testable import SwiftMTP

final class MTPDatasetTests: XCTestCase {
    func testUInt32ArrayDatasetUsesCountAndLittleEndianElements() throws {
        let dataset = MTPUInt32Array(values: [0x1122_3344, 0xAABB_CCDD])
        XCTAssertEqual(
            dataset.encoded(),
            Data([0x02, 0x00, 0x00, 0x00,
                  0x44, 0x33, 0x22, 0x11,
                  0xDD, 0xCC, 0xBB, 0xAA])
        )
        XCTAssertEqual(try MTPUInt32Array.decode(dataset.encoded()), dataset)
    }

    func testObjectInfoCompressedSizeKeepsExactValuesAndUsesOwnSentinel() {
        XCTAssertEqual(MTPObjectInfoDataset.compressedSizeField(for: 0xFFFF_FFFE), 0xFFFF_FFFE)
        XCTAssertEqual(MTPObjectInfoDataset.compressedSizeField(for: 0xFFFF_FFFF), 0xFFFF_FFFF)
        XCTAssertEqual(MTPObjectInfoDataset.compressedSizeField(for: 0x1_0000_0000), 0xFFFF_FFFF)
    }

    func testUInt32ArrayRejectsTrailingAndTruncatedInput() {
        XCTAssertThrowsError(try MTPUInt32Array.decode(Data([0x01, 0x00, 0x00])))
        XCTAssertThrowsError(
            try MTPUInt32Array.decode(Data([0x00, 0x00, 0x00, 0x00, 0xAA]))
        )
    }
}
