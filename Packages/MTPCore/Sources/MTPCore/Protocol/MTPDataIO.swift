import Foundation

/// 数据接收器(getObject 下载时,设备数据流式写入)。对照 Go runTransaction 的 dest io.Writer。
/// 实现:FileHandle(写盘)/ MemoryDataSink(内存缓冲)。
public protocol MTPDataSink {
    func write(_ bytes: [UInt8]) throws
}

/// 内存 sink(测试/小对象用)。对照 Go NullWriter / bytes.Buffer。
public final class MemoryDataSink: MTPDataSink {
    public private(set) var data: [UInt8] = []
    public init() {}
    public func write(_ bytes: [UInt8]) throws { data.append(contentsOf: bytes) }
}
