import Foundation

/// MTP 二进制解码错误。
/// 仅声明当前实际使用的 case(YAGNI);readMTPString/readMTPTime 引入时按需扩展。
public enum MTPDecodeError: Error, Equatable {
    case endOfData
    /// MTP 时间字符串无法解析(三变体均失败)。携带原始字符串便于诊断。
    case invalidTime(String)
    /// M-4:数组长度前缀声明的元素数超过全局上限(防恶意设备声明巨量 → 巨量内存)。
    /// 携带实际声明的 count 便于诊断。
    case arrayTooLarge(count: Int)
}

/// 数组读取安全策略(Plan 1 final review M-4)。
/// 恶意/损坏的设备可在数组长度前缀声明天文数字 count,导致一次性预分配巨量内存。
/// readU32Array/readU16Array 读到 count 后先校验,超限直接抛错,不预分配。
public enum MTPReadPolicy {
    /// 单数组字段最大元素数(防恶意设备声明巨量)。
    /// 4M 个 u32 = 16MB,远超真实 MTP 数组(StorageID/ObjectHandle 实际几十到几千)。
    public static let maxArrayElementCount: Int = 4_000_000
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
        let s = try _read(1)
        return s[s.startIndex]
    }
    public mutating func readU16() throws -> UInt16 {
        let s = try _read(2)
        var v: UInt16 = 0
        for k in 0..<2 { v |= UInt16(s[s.startIndex + k]) << (8 * k) }
        return v
    }
    public mutating func readU32() throws -> UInt32 {
        let s = try _read(4)
        var v: UInt32 = 0
        for k in 0..<4 { v |= UInt32(s[s.startIndex + k]) << (8 * k) }
        return v
    }
    public mutating func readU64() throws -> UInt64 {
        let s = try _read(8)
        var v: UInt64 = 0
        for k in 0..<8 { v |= UInt64(s[s.startIndex + k]) << (8 * k) }
        return v
    }
    public mutating func readBytes(_ count: Int) throws -> [UInt8] {
        // 负 count 是调用方契约违反(非数据问题),用 precondition 而非 throw。
        precondition(count >= 0, "readBytes count must be non-negative")
        let s = try _read(count)
        return Array(s)
    }
}

public extension MTPReader {
    /// 读 u32 长度前缀的 UInt32 数组。对应 Go encoding.go decodeArray(uint32)。
    /// 线序:小端 u32 count → count 个小端 u32。
    /// M-4 双重校验:count 超全局上限 → arrayTooLarge;count*sizeof 超 remaining → endOfData。
    mutating func readU32Array() throws -> [UInt32] {
        let count = Int(try readU32())
        try checkArrayBounds(count: count, elementSize: 4)
        var arr = [UInt32](repeating: 0, count: count)
        for i in 0..<count { arr[i] = try readU32() }
        return arr
    }

    /// 读 u32 长度前缀的 UInt16 数组。对应 Go encoding.go decodeArray(uint16)。
    /// 线序:小端 u32 count → count 个小端 u16。
    /// M-4 双重校验:count 超全局上限 → arrayTooLarge;count*sizeof 超 remaining → endOfData。
    mutating func readU16Array() throws -> [UInt16] {
        let count = Int(try readU32())
        try checkArrayBounds(count: count, elementSize: 2)
        var arr = [UInt16](repeating: 0, count: count)
        for i in 0..<count { arr[i] = try readU16() }
        return arr
    }

    /// M-4 数组双重上限校验(私有,供 readU32Array/readU16Array 复用)。
    /// 1. count <= maxArrayElementCount —— 全局上限(防恶意设备声明巨量)。
    /// 2. count*elementSize <= remaining —— 声明不超出实际剩余字节。
    /// 超任一 → 抛错(不预分配,避免内存放大)。
    @inline(__always)
    private mutating func checkArrayBounds(count: Int, elementSize: Int) throws {
        guard count <= MTPReadPolicy.maxArrayElementCount else {
            throw MTPDecodeError.arrayTooLarge(count: count)
        }
        guard count * elementSize <= remaining else {
            throw MTPDecodeError.endOfData
        }
    }
}
