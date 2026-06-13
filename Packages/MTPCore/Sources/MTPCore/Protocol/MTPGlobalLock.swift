import Foundation

/// 全局串行锁,保护所有 libusb 调用(对齐 Go deviceMu 进程级单锁,设计 §5.5)。
/// libusb 同步 API 非线程安全,同一 handle 并发 transfer 会崩。所有 libusb 调用必须经此串行。
enum MTPGlobalLock {
    private static let queue = DispatchQueue(label: "com.swiftmtp.mtp.libusb.serial")
    static func sync<T>(_ body: () throws -> T) rethrows -> T { try queue.sync(execute: body) }
}
