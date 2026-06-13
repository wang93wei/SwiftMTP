/// MTP/PTP Response Code。值对照 Go mtp/const.go。
/// 注:Go const.go 无 RC_ObjectNotFound;对象未找到用 invalidObjectHandle(0x2009)。
public enum ReturnCode: UInt16 {
    case ok = 0x2001
    case generalError = 0x2002
    case sessionNotOpen = 0x2003
    case invalidTransactionID = 0x2004
    case operationNotSupported = 0x2005
    case incompleteTransfer = 0x2007
    case invalidStorageId = 0x2008
    case invalidObjectHandle = 0x2009   // 对象未找到映射到此
    case accessDenied = 0x200F
    case storeNotAvailable = 0x2013
    case deviceBusy = 0x2019
    case sessionAlreadyOpened = 0x201E
    case transactionCanceled = 0x201F
}
