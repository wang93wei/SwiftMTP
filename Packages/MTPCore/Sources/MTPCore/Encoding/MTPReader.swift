import Foundation

/// MTP 二进制解码错误。
public enum MTPDecodeError: Error, Equatable {
    case endOfData
    case invalidString
    case invalidTime(String)
    case underflow
}

/// 小端字节流读取器。对应 Go encoding.go 的 binary.LittleEndian + io.Reader 读取。
public struct MTPReader {
    private let data: [UInt8]
    private(set) var offset: Int = 0

    public init(_ data: Data) { self.data = Array(data) }
    public init(_ bytes: [UInt8]) { self.data = bytes }

    public var isAtEnd: Bool { offset >= data.count }
    public var remaining: Int { data.count - offset }

    @inline(__always)
    private mutating func _read(_ count: Int) throws -> ArraySlice<UInt8> {
        guard offset + count <= data.count else { throw MTPDecodeError.endOfData }
        let slice = data[offset..<(offset + count)]
        offset += count
        return slice
    }

    public mutating func readU8() throws -> UInt8 {
        let s = try _read(1); return s[s.startIndex]
    }
    public mutating func readU16() throws -> UInt16 {
        let s = try _read(2)
        return UInt16(s[s.startIndex]) | (UInt16(s[s.startIndex + 1]) << 8)
    }
    public mutating func readU32() throws -> UInt32 {
        let s = try _read(4)
        let i = s.startIndex
        return UInt32(s[i]) | (UInt32(s[i + 1]) << 8) | (UInt32(s[i + 2]) << 16) | (UInt32(s[i + 3]) << 24)
    }
    public mutating func readU64() throws -> UInt64 {
        let s = try _read(8)
        let i = s.startIndex
        var v: UInt64 = 0
        for k in 0..<8 { v |= UInt64(s[i + k]) << (8 * k) }
        return v
    }
    public mutating func readBytes(_ count: Int) throws -> [UInt8] {
        guard count >= 0 else { throw MTPDecodeError.underflow }
        let s = try _read(count)
        return Array(s)
    }
}
