import Clibusb

/// libusb 调用错误(返回码 < 0)。携带原始码 + 人类可读串。
public struct MTPUSBError: Error, Equatable {
    public let code: Int32
    public let message: String
    public init(code: Int32) {
        self.code = code
        self.message = String(cString: libusb_strerror(code))
    }
}

/// MTP 设备/协议错误。
public enum MTPError: Error, Equatable {
    case notOpen
    case alreadyOpen
    case noMTPInInterface          // P3:接口串不含 MTP/CDC/ACM
    case needsInfoFallback         // P4:interfaceStringIndex==0,需 GetDeviceInfo 兜底(Plan 2c 补)
    case notMTPExtension(String)   // P4:MTPExtension 不含 microsoft/fujifilm
    case libusb(MTPUSBError)
    case rcError(ReturnCode)       // MTP 响应非 OK(如 SessionAlreadyOpened),对照 Go mtp.go RCError
    case syncError(String)         // 事务失同步(type 错/transactionID 不匹配)
}

/// 检查 libusb 返回码,< 0 转 throw MTPUSBError。
@discardableResult
func checkLibusb(_ r: Int32) throws -> Int32 {
    if r < 0 { throw MTPError.libusb(MTPUSBError(code: r)) }
    return r
}
