import Foundation

nonisolated struct MTPBinaryWriter: Sendable {
    private(set) var data = Data()

    mutating func write(_ value: UInt8) {
        data.append(value)
    }

    mutating func write(_ value: UInt16) {
        appendLittleEndian(value, byteCount: 2)
    }

    mutating func write(_ value: UInt32) {
        appendLittleEndian(value, byteCount: 4)
    }

    mutating func write(_ value: UInt64) {
        appendLittleEndian(value, byteCount: 8)
    }

    mutating func write(_ bytes: Data) {
        data.append(bytes)
    }

    mutating func writeMTPString(_ value: String) throws {
        guard !value.utf16.contains(0) else {
            throw MTPCoreError.invalidInput("MTP strings cannot contain an embedded null")
        }
        let codeUnits = Array(value.utf16)
        guard codeUnits.count <= 254 else {
            throw MTPCoreError.invalidInput("MTP string exceeds 254 UTF-16 code units")
        }
        guard !codeUnits.isEmpty else {
            write(UInt8(0))
            return
        }

        write(UInt8(codeUnits.count + 1))
        for codeUnit in codeUnits {
            write(codeUnit)
        }
        write(UInt16(0))
    }

    private mutating func appendLittleEndian<T: FixedWidthInteger>(
        _ value: T,
        byteCount: Int
    ) {
        for index in 0..<byteCount {
            data.append(UInt8(truncatingIfNeeded: value >> T(index * 8)))
        }
    }
}
