import Clibusb
import Foundation

/// 单次 USB bulk 传输(经 MTPGlobalLock 局部加锁)。对照 Go usb.go:683 BulkTransfer。
///
/// ⚠️ 缓冲生命周期:调用方传入的 `buffer` 指针须在本次 libusb_bulk_transfer 期间保持有效。
/// 推荐用法是 `withUnsafeMutableBufferPointer` 闭包限定,绝不逃逸闭包外。
/// 每个调用点局部加锁(非整事务加锁),避免 runTransaction 编排方法重入 MTPGlobalLock 死锁。
///
/// - Parameters:
///   - handle: libusb 设备句柄(由 MTPDevice.open 持有)。
///   - endpoint: 端点地址(sendEP 发 / fetchEP 收)。
///   - buffer: 预分配缓冲(发送数据 或 接收缓冲)。
///   - length: 缓冲容量(字节数)。
///   - timeout: 超时(毫秒)。
/// - Returns: 实际传输字节数。
/// - Throws: libusb 返回码 < 0 转 `MTPError.libusb`。
func bulkTransfer(_ handle: OpaquePointer, endpoint: UInt8,
                  buffer: UnsafeMutablePointer<UInt8>, length: Int,
                  timeout: UInt32) throws -> Int {
    try MTPGlobalLock.sync {
        var transferred: Int32 = 0
        let r = libusb_bulk_transfer(handle, endpoint, buffer, Int32(length), &transferred, timeout)
        try checkLibusb(r)
        return Int(transferred)
    }
}
