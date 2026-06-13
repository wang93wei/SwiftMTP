import Foundation

/// bulk header 解析结果(值类型,12 字节小端映射)。供 parseBulkHeader 返回。
public struct MTPBulkHeaderParsed: Equatable {
    public let length: UInt32
    public let type: ContainerType
    public let code: UInt16
    public let transactionID: UInt32

    public init(length: UInt32, type: ContainerType, code: UInt16, transactionID: UInt32) {
        self.length = length
        self.type = type
        self.code = code
        self.transactionID = transactionID
    }
}

/// 解析 12 字节小端 bulk header。对照 Go fetchPacket 的 binary.Read(mtp.go:333)。
/// 线序:length u32 @0,type u16 @4,code u16 @6,transactionID u32 @8。
/// 字节不足 12 或 type 非法 → 抛 endOfData。
public func parseBulkHeader(_ bytes: [UInt8]) throws -> MTPBulkHeaderParsed {
    var reader = MTPReader(bytes)
    let length = try reader.readU32()
    let typeRaw = try reader.readU16()
    let code = try reader.readU16()
    let tid = try reader.readU32()
    guard let type = ContainerType(rawValue: typeRaw) else {
        throw MTPDecodeError.endOfData  // 非法 container type
    }
    return MTPBulkHeaderParsed(length: length, type: type, code: code, transactionID: tid)
}

/// 解码 response 参数。对照 Go decodeRep(mtp.go:347-355)。
/// restLen = declaredLength - 12;nParam = restLen/4;逐小端 u32。
/// declaredLength < 12(无 payload 区)或声明 > 实际 rest → 抛 endOfData(对照 mtp.go:348)。
public func decodeResponseParams(declaredLength: UInt32, rest: [UInt8]) throws -> [UInt32] {
    let restLen = Int(declaredLength) - MTPConstants.usbHeaderLength
    if restLen < 0 { throw MTPDecodeError.endOfData }
    if restLen > rest.count {
        throw MTPDecodeError.endOfData  // 声明 > 实际(对照 mtp.go:348)
    }
    let nParam = restLen / 4
    var params = [UInt32]()
    params.reserveCapacity(nParam)
    var reader = MTPReader(rest)
    for _ in 0..<nParam { params.append(try reader.readU32()) }
    return params
}

/// P1 SeparateHeader 探测。对照 Go mtp.go:464。
/// 首包 n==12(仅 header)&& rest 空 && n<声明总长 → 设备走分离头模式。
public func shouldEnableSeparateHeader(firstPacketBytes n: Int, restLength: Int,
                                       declaredContainerLength: UInt32) -> Bool {
    n == MTPConstants.usbHeaderLength
        && restLength == 0
        && UInt32(n) < declaredContainerLength
}

/// P5 SessionAlreadyOpened 判定。对照 Go mtp.go:669 RCError(RC_SessionAlreadyOpened)。
/// 仅匹配 MTPError.rcError(.sessionAlreadyOpened);其余错误(libusb/其他 rc/sync)返回 false。
public func isSessionAlreadyOpened(_ error: Error) -> Bool {
    if case let MTPError.rcError(code) = error, code == .sessionAlreadyOpened { return true }
    return false
}

/// bulkWrite ZLP 判定(Plan 2d 写路径用)。对照 Go mtp.go:597。
/// 末包恰为 packetSize 整数倍且非空 → 需补零长度包(shorten the stream terminator)。
public func needsZeroLengthPacket(lastTransferBytes: Int, packetSize: Int) -> Bool {
    packetSize > 0 && lastTransferBytes > 0 && lastTransferBytes % packetSize == 0
}
