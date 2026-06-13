import Foundation

/// MTP 结构体的逐字段解码协议。对应 Go encoding.go 的 reflect-based Decode,
/// Swift 改为每个结构体显式实现(替代 reflect),保证线序一处正确。
public protocol MTPDecodable {
    init(from reader: inout MTPReader) throws
}

/// 顶层 decode 入口:从原始字节解码出 MTPDecodable 结构体。
public func decode<T: MTPDecodable>(_ data: Data, as type: T.Type = T.self) throws -> T {
    var reader = MTPReader(data)
    return try T(from: &reader)
}
