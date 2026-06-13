import Clibusb

// MTPCore: MTP/PTP 协议纯逻辑层(编解码、常量、线协议)。
// Clibusb 提供 libusb C 符号;Protocol 层(Plan 2b)将调用 USB 传输 API。

/// libusb 版本探针:验证 modulemap 配置正确(import Clibusb 能编译 + 链接 libusb 符号)。
/// Plan 2b Protocol 层真正调用 libusb 后,此探针可移除。
public func _libusbVersionProbe() -> String {
    guard let v = libusb_get_version() else { return "unknown" }
    return "\(v.pointee.major).\(v.pointee.minor).\(v.pointee.micro)"
}
