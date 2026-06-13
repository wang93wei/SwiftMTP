import Clibusb
import Foundation

/// MTP 设备封装。@unchecked Sendable:线程安全全靠 MTPGlobalLock 串行化所有 libusb 调用
/// (非 actor,符合 project-exemption 文件传输豁免)。对应 Go mtp.go Device。
///
/// Plan 2b 仅设备识别层(枚举/描述符/端点拓扑/open P3/close);
/// 事务层(runTransaction/bulkRead/session/P1/P2/P4/P5 编排)在 Plan 2c。
final class MTPDevice: @unchecked Sendable {
    /// libusb_device_handle*。nil = 未 open。Open 后非空,close 后置 nil。
    /// OpaquePointer! 隐式解包,所有访问前必须 guard(否则 nil 解引用崩溃)。
    private var handle: OpaquePointer?
    /// libusb_device*。init 时 ref_device 持有,deinit 时 unref_device 释放。
    private let device: OpaquePointer

    /// 设备描述符快照(值类型,脱离 C 指针生命周期)。
    let deviceDescriptor: DeviceDescriptorSnapshot
    /// MTP 接口描述符快照(含接口号/接口串索引/3 端点)。
    let interfaceDescriptor: InterfaceDescriptorSnapshot
    /// 配置值(bConfigurationValue,用于 select_config,Plan 2c 事务层用)。
    let configValue: UInt8
    /// MTP 三端点地址(OUT-BULK 发送 / IN-BULK 接收 / IN-INTERRUPT 事件)。
    let sendEP: UInt8
    let fetchEP: UInt8
    let eventEP: UInt8

    /// 传输超时 ms(对应 Go mtp.go:154 默认 2000)。
    var timeout: Int32 = 2000
    /// SeparateHeader 运行时探测标志(Plan 2c 补,对应 Go mtp.go SeparateHeader)。
    var separateHeader: Bool = false
    /// 接口是否已 claim(open 时置 true,close 时置 false)。防止重复 release。
    private(set) var claimed: Bool = false
    // session 管理在 Plan 2c 加(OpenSession/CloseSession/Configure)。

    /// 从已枚举的 libusb_device 构造。
    /// 立即 libusb_ref_device 持有引用(对应 Go select.go:40 d.Ref())。
    /// 读设备描述符 + 遍历配置找 3 端点 MTP 接口。
    /// 调用方负责保证 device 有效(通常来自 libusb_get_device_list,列表释放前)。
    init(device: OpaquePointer) throws {
        self.device = device
        // 持有设备引用计数 +1(对应 Go select.go:40 d.Ref())。
        // 重要:必须在 libusb_free_device_list 之前 ref,否则 free list 后指针失效。
        _ = libusb_ref_device(device)

        // 读设备描述符(对应 Go usb.go:549)。
        var dd = libusb_device_descriptor()
        try checkLibusb(libusb_get_device_descriptor(device, &dd))
        self.deviceDescriptor = DeviceDescriptorSnapshot(
            idVendor: dd.idVendor, idProduct: dd.idProduct,
            iManufacturer: dd.iManufacturer, iProduct: dd.iProduct,
            iSerialNumber: dd.iSerialNumber, numConfigurations: dd.bNumConfigurations)

        // 遍历配置找恰好 3 端点 + 三类齐全的 MTP 接口(对应 Go select.go:11-49)。
        let (iface, config, eps) = try MTPDevice.findMTPInterface(device: device, dd: dd)
        let classification = classifyEndpoints(eps)
        // 候选已由 findMTPInterface 内 isMTPCandidate 筛过,三类必齐;这里解包防御。
        guard let send = classification.sendEP,
              let fetch = classification.fetchEP,
              let event = classification.eventEP else {
            throw MTPError.libusb(MTPUSBError(code: LIBUSB_ERROR_OTHER.rawValue))
        }

        self.interfaceDescriptor = iface
        self.configValue = config
        self.sendEP = send
        self.fetchEP = fetch
        self.eventEP = event
        self.handle = nil
    }

    deinit {
        // 设备引用计数 -1(对应 Go mtp.go:131 Done)。ref/unref 配对。
        libusb_unref_device(device)
    }

    /// 遍历设备所有配置,找恰好 3 端点 + 三类齐全(OUT-BULK/IN-BULK/IN-INT)的 MTP 接口。
    /// 返回:(接口快照, bConfigurationValue, 端点数组)。
    ///
    /// ⚠️ C 指针生命周期:UnsafeBufferPointer 遍历**必须在** `defer { libusb_free_config_descriptor }`
    /// **之内**完成。EndpointSnapshot 拷成值类型后方可跨调用持有(绝不存 UnsafePointer)。
    /// 对应 Go select.go:11-49。
    private static func findMTPInterface(device: OpaquePointer, dd: libusb_device_descriptor) throws
        -> (InterfaceDescriptorSnapshot, UInt8, [EndpointSnapshot]) {
        for ci in 0..<Int(dd.bNumConfigurations) {
            var cfgPtr: UnsafeMutablePointer<libusb_config_descriptor>?
            try checkLibusb(libusb_get_config_descriptor(device, UInt8(ci), &cfgPtr))
            // ⚠️ 释放保护:以下所有 C 指针遍历必须在 defer 之前/之内完成,并拷成值类型。
            guard let cfgPtr else { continue }
            defer { libusb_free_config_descriptor(cfgPtr) }

            let cfg = cfgPtr.pointee
            let nInterfaces = Int(cfg.bNumInterfaces)
            // `interface` 是 Swift 关键字,必须用反引号转义。
            let ifaces = UnsafeBufferPointer(start: cfg.`interface`, count: nInterfaces)
            for iface in ifaces {
                let nAlt = Int(iface.num_altsetting)
                let alts = UnsafeBufferPointer(start: iface.altsetting, count: nAlt)
                for a in alts {
                    let nEP = Int(a.bNumEndpoints)
                    let eps = UnsafeBufferPointer(start: a.endpoint, count: nEP).map {
                        EndpointSnapshot(address: $0.bEndpointAddress,
                                         attributes: $0.bmAttributes,
                                         maxPacketSize: $0.wMaxPacketSize)
                    }
                    // 候选判定:恰好 3 端点 + 三类齐全。
                    if isMTPCandidate(eps) {
                        let ifaceSnap = InterfaceDescriptorSnapshot(
                            interfaceNumber: a.bInterfaceNumber,
                            interfaceStringIndex: a.iInterface,
                            endpoints: eps)
                        // 值类型已拷贝,可安全跨 defer 边界返回。
                        return (ifaceSnap, cfg.bConfigurationValue, eps)
                    }
                }
            }
        }
        // 未找到 3 端点 MTP 接口。
        throw MTPError.libusb(MTPUSBError(code: LIBUSB_ERROR_OTHER.rawValue))
    }
}
