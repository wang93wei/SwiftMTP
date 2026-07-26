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
