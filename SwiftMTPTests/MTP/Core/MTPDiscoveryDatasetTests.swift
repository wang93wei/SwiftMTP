import XCTest
@testable import SwiftMTP

final class MTPDiscoveryDatasetTests: XCTestCase {
    func testDeviceInfoDecodesRequiredIdentityFieldsAndArrays() throws {
        var writer = MTPBinaryWriter()
        writer.write(UInt16(100))
        writer.write(UInt32(6))
        writer.write(UInt16(101))
        try writer.writeMTPString("microsoft.com: 1.0;")
        writer.write(UInt16(0))
        writer.writeUInt16Array([0x1001, 0x1004, 0x1005])
        writer.writeUInt16Array([0x4002])
        writer.writeUInt16Array([0x5001])
        writer.writeUInt16Array([])
        writer.writeUInt16Array([0x3801])
        try writer.writeMTPString("Acme")
        try writer.writeMTPString("Phone X")
        try writer.writeMTPString("1.2.3")
        try writer.writeMTPString("secret-serial")

        let info = try MTPDeviceInfoDataset.decode(writer.data)

        XCTAssertEqual(info.standardVersion, 100)
        XCTAssertEqual(info.vendorExtensionID, 6)
        XCTAssertEqual(info.operationsSupported, [0x1001, 0x1004, 0x1005])
        XCTAssertEqual(info.eventsSupported, [0x4002])
        XCTAssertEqual(info.manufacturer, "Acme")
        XCTAssertEqual(info.model, "Phone X")
        XCTAssertEqual(info.deviceVersion, "1.2.3")
        XCTAssertEqual(info.serialNumber, "secret-serial")
    }

    func testStorageInfoDecodes64BitCapacityAndDescription() throws {
        var writer = MTPBinaryWriter()
        writer.write(UInt16(0x0003))
        writer.write(UInt16(0x0002))
        writer.write(UInt16(0x0000))
        writer.write(UInt64(0x0000_0002_0000_0000))
        writer.write(UInt64(0x0000_0001_8000_0000))
        writer.write(UInt32(42))
        try writer.writeMTPString("Internal shared storage")
        try writer.writeMTPString("Phone")

        let info = try MTPStorageInfoDataset.decode(writer.data)

        XCTAssertEqual(info.storageType, 0x0003)
        XCTAssertEqual(info.fileSystemType, 0x0002)
        XCTAssertEqual(info.maxCapacity, 0x0000_0002_0000_0000)
        XCTAssertEqual(info.freeSpaceInBytes, 0x0000_0001_8000_0000)
        XCTAssertEqual(info.description, "Internal shared storage")
        XCTAssertEqual(info.volumeLabel, "Phone")
    }

    func testDiscoveryDatasetsRejectTruncatedAndTrailingInput() throws {
        XCTAssertThrowsError(try MTPDeviceInfoDataset.decode(Data([0x64])))

        var writer = MTPBinaryWriter()
        writer.write(UInt16(0x0003))
        writer.write(UInt16(0x0002))
        writer.write(UInt16(0x0000))
        writer.write(UInt64(1))
        writer.write(UInt64(1))
        writer.write(UInt32(1))
        try writer.writeMTPString("")
        try writer.writeMTPString("")
        writer.write(UInt8(0xAA))

        XCTAssertThrowsError(try MTPStorageInfoDataset.decode(writer.data))
    }
}

private extension MTPBinaryWriter {
    mutating func writeUInt16Array(_ values: [UInt16]) {
        write(UInt32(values.count))
        values.forEach { write($0) }
    }
}
