/// USB container 类型(runTransaction 三阶段用)。对照 const.go:1930-1933。
public enum ContainerType: UInt16 {
    case undefined = 0x0000
    case command = 0x0001
    case data = 0x0002
    case response = 0x0003
    case event = 0x0004
}

/// MTP/USB 杂项常量。libusb 的 #define 宏在 Swift 不可见,此处自写等价常量。
/// 对照 const.go / types.go / mtp.go / usb.go。
public enum MTPConstants {
    // GetObjectHandles 通配
    public static let gohAllStorage: UInt32 = 0xFFFFFFFF
    public static let gohRootParent: UInt32 = 0xFFFFFFFF
    public static let gohAllFormats: UInt32 = 0x00000000

    // ObjectFormatCode(const.go)
    public static let ofcAssociation: UInt16 = 0x3001  // 文件夹
    public static let ofcUndefined: UInt16 = 0x3000

    // AssociationType
    public static let atGenericFolder: UInt16 = 0x0001

    // USB bulk container 线序长度(types.go:167-168)
    public static let usbHeaderLength: Int = 12            // 2*2 + 2*4(usbBulkHeader)
    public static let usbBulkContainerLength: Int = 32     // 5*4 + usbHeaderLength(usbBulkContainer)

    // bulk 单次最大缓冲(mtp.go:526:The linux usb stack can send 16kb per call)
    public static let bulkTransferBufferSize: Int = 0x4000 // 16384

    // 端点拓扑判定(usb.go:282-289;libusb 宏 Swift 不可见,自写)
    public static let endpointIn: UInt8 = 0x80
    public static let endpointOut: UInt8 = 0x00
    public static let transferTypeBulk: UInt8 = 0x02
    public static let transferTypeInterrupt: UInt8 = 0x03

    // 默认超时(mtp.go:154 Open 内 d.Timeout=2000,毫秒)
    public static let defaultTimeoutMs: Int32 = 2000
}
