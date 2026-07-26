import Foundation

nonisolated struct MTPBinaryReader: Sendable {
    let data: Data
    private(set) var offset = 0

    var remainingCount: Int {
        data.count - offset
    }

    mutating func readUInt8() throws -> UInt8 {
        let bytes = try peekBytes(count: 1)
        offset += 1
        return bytes[bytes.startIndex]
    }

    mutating func readUInt16() throws -> UInt16 {
        try readInteger(byteCount: 2)
    }

    mutating func readUInt32() throws -> UInt32 {
        try readInteger(byteCount: 4)
    }

    mutating func readUInt64() throws -> UInt64 {
        try readInteger(byteCount: 8)
    }

    mutating func readData(count: Int) throws -> Data {
        let bytes = try peekBytes(count: count)
        offset += count
        return Data(bytes)
    }

    mutating func readMTPString() throws -> String {
        let startOffset = offset
        let count = try readUInt8()
        guard count != 0 else {
            return ""
        }

        let byteCount = Int(count) * 2
        do {
            let bytes = try readData(count: byteCount)
            guard bytes.suffix(2) == Data([0x00, 0x00]) else {
                throw MTPCoreError.protocolViolation("MTP string is not null terminated")
            }
            let content = bytes.dropLast(2)
            guard let value = String(data: Data(content), encoding: .utf16LittleEndian) else {
                throw MTPCoreError.protocolViolation("MTP string contains invalid UTF-16LE")
            }
            return value
        } catch {
            offset = startOffset
            throw error
        }
    }

    private mutating func readInteger<T: FixedWidthInteger>(byteCount: Int) throws -> T {
        let bytes = try peekBytes(count: byteCount)
        var value: T = 0
        for (index, byte) in bytes.enumerated() {
            value |= T(byte) << T(index * 8)
        }
        offset += byteCount
        return value
    }

    private func peekBytes(count: Int) throws -> Data.SubSequence {
        guard count >= 0, offset <= data.count, count <= data.count - offset else {
            throw MTPCoreError.protocolViolation(
                "binary input truncated at offset \(offset), requested \(count) bytes"
            )
        }
        // Data slices can have a non-zero startIndex after a framer consumes
        // an earlier container. `offset` is intentionally relative to the
        // reader input, so translate it through the collection indices.
        let start = data.index(data.startIndex, offsetBy: offset)
        let end = data.index(start, offsetBy: count)
        return data[start..<end]
    }
}
