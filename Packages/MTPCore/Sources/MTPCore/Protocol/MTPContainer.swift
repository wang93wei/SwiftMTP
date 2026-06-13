import Foundation

/// MTP 请求(对应 Go types.go:14 Container)。
/// `sessionID`/`transactionID` 由 runTransaction 注入;构造期默认 0。
public struct MTPRequest {
    public var code: OperationCode
    public var params: [UInt32]                // 最多 5 个(对照 Go [5]uint32)
    public var sessionID: UInt32 = 0
    public var transactionID: UInt32 = 0

    public init(code: OperationCode, params: [UInt32] = []) {
        precondition(params.count <= 5, "MTP 请求参数最多 5 个(对照 Go [5]uint32)")
        self.code = code
        self.params = params
    }
}

/// MTP 响应(对应 Go Container rep)。
public struct MTPResponse {
    public var code: ReturnCode
    public var params: [UInt32]
    public var transactionID: UInt32
    public var sessionID: UInt32 = 0

    public init(code: ReturnCode, params: [UInt32] = [], transactionID: UInt32 = 0) {
        self.code = code
        self.params = params
        self.transactionID = transactionID
    }
}

/// USB bulk container header(12 字节,小端)。对照 Go types.go:155 usbBulkHeader。
/// 线序:length u32 @0,type u16 @4,code u16 @6,transactionID u32 @8。
public struct MTPBulkHeader {
    public var length: UInt32          // container 总长(含 header)
    public var type: ContainerType
    public var code: UInt16            // operation/response code
    public var transactionID: UInt32

    /// 从至少 12 字节的小端字节流解析。
    /// 字节不足 12 或 type 非法 → nil。完整解析逻辑见 Task 2 `parseBulkHeader`。
    public init?(leBytes bytes: [UInt8]) {
        guard bytes.count >= MTPConstants.usbHeaderLength else { return nil }
        var r = MTPReader(bytes)
        guard let len = try? r.readU32(),
              let typeRaw = try? r.readU16(),
              let code = try? r.readU16(),
              let tid = try? r.readU32(),
              let type = ContainerType(rawValue: typeRaw) else {
            return nil
        }
        length = len
        self.type = type
        self.code = code
        transactionID = tid
    }

    public init(length: UInt32, type: ContainerType, code: UInt16, transactionID: UInt32) {
        self.length = length
        self.type = type
        self.code = code
        self.transactionID = transactionID
    }
}
