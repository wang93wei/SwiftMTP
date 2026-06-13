import Foundation

/// MTP Uint32Array(GetObjectHandles 的返回形态)。对应 Go types.go Uint32Array +
/// encoding.go decodeArray:u32 长度前缀 + N 个小端 u32。
public struct Uint32Array: MTPDecodable, Equatable {
    public var values: [UInt32]

    public init(from reader: inout MTPReader) throws {
        values = try reader.readU32Array()
    }

    public init(values: [UInt32] = []) { self.values = values }
}
