import Foundation

nonisolated struct MTPUInt32Array: Equatable, Sendable {
    let values: [UInt32]

    func encoded() -> Data {
        var writer = MTPBinaryWriter()
        writer.write(UInt32(values.count))
        for value in values {
            writer.write(value)
        }
        return writer.data
    }

    static func decode(_ data: Data) throws -> Self {
        var reader = MTPBinaryReader(data: data)
        let count = try reader.readUInt32()
        guard UInt64(count) * 4 <= UInt64(reader.remainingCount) else {
            throw MTPCoreError.protocolViolation("UInt32 array dataset is truncated")
        }
        var values: [UInt32] = []
        values.reserveCapacity(Int(count))
        for _ in 0..<count {
            values.append(try reader.readUInt32())
        }
        guard reader.remainingCount == 0 else {
            throw MTPCoreError.protocolViolation("UInt32 array dataset has trailing bytes")
        }
        return Self(values: values)
    }
}

nonisolated struct MTPObjectInfoDataset: Equatable, Sendable {
    let storageID: MTPStorageID
    let objectFormat: UInt16
    let objectSize: UInt64
    let parentObject: MTPObjectID
    let filename: String

    /// ObjectInfo has a separate UInt32 size field: values through
    /// `0xFFFFFFFE` are exact, while larger values use its sentinel.
    static func compressedSizeField(for byteCount: UInt64) -> UInt32 {
        byteCount >= UInt64(UInt32.max) ? UInt32.max : UInt32(byteCount)
    }
}

nonisolated struct MTPDeviceInfoDataset: Equatable, Sendable {
    let standardVersion: UInt16
    let vendorExtensionID: UInt32
    let vendorExtensionVersion: UInt16
    let vendorExtensionDescription: String
    let functionalMode: UInt16
    let operationsSupported: [UInt16]
    let eventsSupported: [UInt16]
    let devicePropertiesSupported: [UInt16]
    let captureFormats: [UInt16]
    let imageFormats: [UInt16]
    let manufacturer: String
    let model: String
    let deviceVersion: String
    let serialNumber: String

    static func decode(_ data: Data) throws -> Self {
        var reader = MTPBinaryReader(data: data)
        let result = Self(
            standardVersion: try reader.readUInt16(),
            vendorExtensionID: try reader.readUInt32(),
            vendorExtensionVersion: try reader.readUInt16(),
            vendorExtensionDescription: try reader.readMTPString(),
            functionalMode: try reader.readUInt16(),
            operationsSupported: try reader.readUInt16Array(),
            eventsSupported: try reader.readUInt16Array(),
            devicePropertiesSupported: try reader.readUInt16Array(),
            captureFormats: try reader.readUInt16Array(),
            imageFormats: try reader.readUInt16Array(),
            manufacturer: try reader.readMTPString(),
            model: try reader.readMTPString(),
            deviceVersion: try reader.readMTPString(),
            serialNumber: try reader.readMTPString()
        )
        guard reader.remainingCount == 0 else {
            throw MTPCoreError.protocolViolation("DeviceInfo dataset has trailing bytes")
        }
        return result
    }
}

nonisolated struct MTPStorageInfoDataset: Equatable, Sendable {
    let storageType: UInt16
    let fileSystemType: UInt16
    let accessCapability: UInt16
    let maxCapacity: UInt64
    let freeSpaceInBytes: UInt64
    let freeSpaceInImages: UInt32
    let description: String
    let volumeLabel: String

    static func decode(_ data: Data) throws -> Self {
        var reader = MTPBinaryReader(data: data)
        let result = Self(
            storageType: try reader.readUInt16(),
            fileSystemType: try reader.readUInt16(),
            accessCapability: try reader.readUInt16(),
            maxCapacity: try reader.readUInt64(),
            freeSpaceInBytes: try reader.readUInt64(),
            freeSpaceInImages: try reader.readUInt32(),
            description: try reader.readMTPString(),
            volumeLabel: try reader.readMTPString()
        )
        guard reader.remainingCount == 0 else {
            throw MTPCoreError.protocolViolation("StorageInfo dataset has trailing bytes")
        }
        return result
    }
}

private extension MTPBinaryReader {
    nonisolated mutating func readUInt16Array() throws -> [UInt16] {
        let count = try readUInt32()
        guard UInt64(count) * 2 <= UInt64(remainingCount) else {
            throw MTPCoreError.protocolViolation("UInt16 array dataset is truncated")
        }
        var values: [UInt16] = []
        values.reserveCapacity(Int(count))
        for _ in 0..<count {
            values.append(try readUInt16())
        }
        return values
    }
}
