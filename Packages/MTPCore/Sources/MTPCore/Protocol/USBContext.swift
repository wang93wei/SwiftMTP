import Clibusb
import Foundation

/// libusb_context 封装。所有设备枚举/传输共享一个 context。
/// 使用:`try USBContext { ctx in ... }`(当前实现为直接 init,deinit 时 libusb_exit)。
/// 线程安全:libusb 调用全部经 MTPGlobalLock 串行(设计 §5.5)。
final class USBContext {
    /// libusb_context 不透明指针。libusb_context 是前向声明结构体,Swift 导入后用 OpaquePointer 持有。
    private let raw: OpaquePointer

    init() throws {
        var ctx: OpaquePointer?
        try MTPGlobalLock.sync {
            _ = try checkLibusb(libusb_init(&ctx))
        }
        guard let c = ctx else {
            // libusb_init 返回 0 成功但 ctx 仍 nil(理论不发生)。
            throw MTPError.libusb(MTPUSBError(code: LIBUSB_ERROR_OTHER.rawValue))
        }
        self.raw = c
    }

    deinit {
        // libusb_exit 可空 ctx(NULL 表示默认 context);此处释放本 context。
        libusb_exit(raw)
    }

    /// 暴露给 MTPDevice / 枚举函数使用(仅 libusb_* 函数需要该指针)。
    var pointer: OpaquePointer { raw }
}
