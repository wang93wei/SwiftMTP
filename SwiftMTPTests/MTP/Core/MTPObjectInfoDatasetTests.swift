import XCTest
@testable import SwiftMTP

final class MTPObjectInfoDatasetTests: XCTestCase {
    func testDecodesCompleteFileDatasetWithEmojiAndOffsetTimestamp() throws {
        let bytes = Data([
            0x01, 0x00, 0x01, 0x00,
            0x00, 0x30,
            0x00, 0x00,
            0x2A, 0x00, 0x00, 0x00,
            0x00, 0x00,
            0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00,
            0xFF, 0xFF, 0xFF, 0xFF,
            0x00, 0x00,
            0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00,
            0x08, 0x41, 0x00, 0x3D, 0xD8, 0x00, 0xDE, 0x2E, 0x00, 0x74, 0x00, 0x78, 0x00, 0x74, 0x00, 0x00, 0x00,
            0x00,
            0x15, 0x32, 0x00, 0x30, 0x00, 0x32, 0x00, 0x36, 0x00, 0x30, 0x00, 0x37, 0x00, 0x33, 0x00, 0x30, 0x00,
            0x54, 0x00, 0x31, 0x00, 0x32, 0x00, 0x30, 0x00, 0x30, 0x00, 0x30, 0x00, 0x30, 0x00, 0x2B, 0x00, 0x30, 0x00,
            0x38, 0x00, 0x30, 0x00, 0x30, 0x00, 0x00, 0x00,
            0x00,
        ])

        let dataset = try MTPObjectInfoDataset.decode(bytes)

        XCTAssertEqual(dataset.storageID.rawValue, 0x0001_0001)
        XCTAssertEqual(dataset.objectFormat, 0x3000)
        XCTAssertEqual(dataset.objectSize, 42)
        XCTAssertEqual(dataset.parentObject, .root)
        XCTAssertEqual(dataset.filename, "A😀.txt")
        XCTAssertEqual(dataset.modificationDateString, "20260730T120000+0800")
        XCTAssertNotNil(dataset.modificationDate)
        XCTAssertEqual(try dataset.encoded(), bytes)
    }

    func testDecodesWireZeroParentAsRoot() throws {
        var bytes = try MTPObjectInfoDataset.file(
            storageID: try MTPStorageID(validating: 1),
            parentObject: .root,
            name: "root.txt",
            size: 1
        ).encoded()
        bytes.replaceSubrange(38..<42, with: repeatElement(UInt8.zero, count: 4))

        let dataset = try MTPObjectInfoDataset.decode(bytes)

        XCTAssertEqual(dataset.parentObject, .root)
    }

    func testFolderEncodingUsesAssociationFormatAndExactUTF16CodeUnits() throws {
        let storageID = try MTPStorageID(validating: 0x0001_0001)
        let dataset = try MTPObjectInfoDataset.folder(
            storageID: storageID,
            parentObject: .root,
            name: "相册😀"
        )

        let encoded = try dataset.encoded()
        let decoded = try MTPObjectInfoDataset.decode(encoded)

        XCTAssertEqual(decoded.objectFormat, 0x3001)
        XCTAssertEqual(decoded.associationType, 1)
        XCTAssertEqual(decoded.objectSize, 0)
        XCTAssertEqual(decoded.filename, "相册😀")
    }

    func testFileEncodingUsesExactCompressedSizeBoundaryAndSentinel() throws {
        let storageID = try MTPStorageID(validating: 1)

        for (size, expectedField) in [
            (UInt64(0xFFFF_FFFE), UInt32(0xFFFF_FFFE)),
            (UInt64(0xFFFF_FFFF), UInt32.max),
            (UInt64(0x1_0000_0000), UInt32.max),
        ] {
            let encoded = try MTPObjectInfoDataset.file(
                storageID: storageID,
                parentObject: .root,
                name: "文档😀.bin",
                size: size
            ).encoded()
            var reader = MTPBinaryReader(data: encoded)
            _ = try reader.readUInt32()
            _ = try reader.readUInt16()
            _ = try reader.readUInt16()

            XCTAssertEqual(try reader.readUInt32(), expectedField)
        }
    }

    func testFileNameRejectsEmbeddedNullAndOverlongUTF16() throws {
        let storageID = try MTPStorageID(validating: 1)

        XCTAssertThrowsError(
            try MTPObjectInfoDataset.file(
                storageID: storageID,
                parentObject: .root,
                name: "bad\u{0}name",
                size: 0
            )
        ) {
            guard case .invalidInput = $0 as? MTPCoreError else {
                return XCTFail("expected embedded-null rejection, got \($0)")
            }
        }
        XCTAssertThrowsError(
            try MTPObjectInfoDataset.file(
                storageID: storageID,
                parentObject: .root,
                name: String(repeating: "😀", count: 128),
                size: 0
            )
        ) {
            guard case .invalidInput = $0 as? MTPCoreError else {
                return XCTFail("expected UTF-16 length rejection, got \($0)")
            }
        }
        XCTAssertThrowsError(
            try MTPObjectInfoDataset.file(
                storageID: storageID,
                parentObject: .root,
                name: "line\nbreak.bin",
                size: 0
            )
        ) {
            guard case .invalidInput = $0 as? MTPCoreError else {
                return XCTFail("expected control-character rejection, got \($0)")
            }
        }
    }

    func testSentinelSizeUTCAndEmptyOptionalStringsRoundTrip() throws {
        let original = try MTPObjectInfoDataset(
            storageID: try MTPStorageID(validating: 1),
            objectFormat: 0x3000,
            objectSize: UInt64.max,
            parentObject: .root,
            filename: "文档.txt",
            modificationDateString: "20260730T040000Z"
        )

        let decoded = try MTPObjectInfoDataset.decode(original.encoded())

        XCTAssertEqual(decoded.objectSize, UInt64(UInt32.max))
        XCTAssertEqual(decoded.captureDateString, "")
        XCTAssertEqual(decoded.keywords, "")
        XCTAssertEqual(decoded.modificationDateString, "20260730T040000Z")
        XCTAssertNotNil(decoded.modificationDate)
    }

    func testAcceptsMTPTimestampWithoutTimezone() throws {
        let dataset = try MTPObjectInfoDataset(
            storageID: try MTPStorageID(validating: 1),
            objectFormat: 0x3000,
            objectSize: 1,
            parentObject: .root,
            filename: "root.txt",
            modificationDateString: "20260702T034455"
        )

        XCTAssertEqual(dataset.modificationDateString, "20260702T034455")
        XCTAssertNotNil(dataset.modificationDate)
    }

    func testRejectsTruncatedTrailingEmbeddedNullAndMalformedTimestamp() throws {
        let valid = try MTPObjectInfoDataset.folder(
            storageID: try MTPStorageID(validating: 1),
            parentObject: .root,
            name: "ok"
        ).encoded()

        XCTAssertThrowsError(try MTPObjectInfoDataset.decode(Data(valid.dropLast())))
        XCTAssertThrowsError(try MTPObjectInfoDataset.decode(valid + Data([0xAA])))
        var embeddedNull = valid
        embeddedNull[55] = 0
        embeddedNull[56] = 0
        XCTAssertThrowsError(try MTPObjectInfoDataset.decode(embeddedNull))
        XCTAssertThrowsError(
            try MTPObjectInfoDataset.folder(
                storageID: try MTPStorageID(validating: 1),
                parentObject: .root,
                name: "bad\u{0}name"
            )
        )
        XCTAssertThrowsError(
            try MTPObjectInfoDataset(
                storageID: try MTPStorageID(validating: 1),
                objectFormat: 0x3000,
                objectSize: 1,
                parentObject: .root,
                filename: "a",
                modificationDateString: "not-a-date"
            )
        )
        XCTAssertThrowsError(
            try MTPObjectInfoDataset(
                storageID: try MTPStorageID(validating: 1),
                objectFormat: 0x3000,
                objectSize: 1,
                parentObject: .root,
                filename: "a",
                modificationDateString: "20260230T120000Z"
            )
        )
    }
}
