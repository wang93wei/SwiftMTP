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

extension MTPDevice {
    /// 枚举所有 MTP 候选设备(对应 Go select.go:52 FindDevices)。
    /// 仅做端点拓扑判定(3 端点 + 三类齐全),未 open。
    ///
    /// 引用计数:libusb_get_device_list 返回的设备初始引用计数为 1;
    /// `MTPDevice.init` 内立即 ref_device(+1),故 libusb_free_device_list(unref_devices=1)
    /// 释放列表引用后,候选设备的 +1 仍被 MTPDevice 持有,deinit 时 unref 释放(对应 Go select.go:66-68)。
    /// 非候选/构造失败的设备直接被 free list 回收。
    ///
    /// - Parameter context: 共享的 libusb context。
    /// - Returns: 拓扑判定的 MTP 候选数组(调用方负责 close/deinit)。
    static func findMTPDevices(in context: USBContext) throws -> [MTPDevice] {
        try MTPGlobalLock.sync {
            // libusb_device 是不透明结构体 typedef,Swift 不暴露为具名类型,
            // 故 libusb_get_device_list 的 out 参数元素类型即 OpaquePointer。
            var list: UnsafeMutablePointer<OpaquePointer?>?
            let count = libusb_get_device_list(context.pointer, &list)
            // count < 0 为 libusb 错误码。
            try checkLibusb(Int32(count))
            guard let list, count > 0 else {
                if let list { libusb_free_device_list(list, 1) }
                return []
            }
            // unref_devices=1:释放列表对每个设备的引用(MTPDevice.init 已单独 ref 持有候选)。
            defer { libusb_free_device_list(list, 1) }

            var devices: [MTPDevice] = []
            for i in 0..<count {
                guard let dev = list[i] else { continue }
                // 读描述符 + 端点拓扑判定在 init 内完成。
                // 非 3 端点 / 读描述符失败 → 抛错 → try? 跳过该设备(对应 Go select.go 过滤)。
                if let mtp = try? MTPDevice(device: dev) {
                    devices.append(mtp)
                }
            }
            return devices
        }
    }

    /// 打开设备:libusb_open + claim_interface + 接口串校验(P3)。
    /// 对应 Go mtp.go:152-203(仅 P3 分支)。
    ///
    /// P4 分支(interfaceStringIndex==0 的 microsoft/fujifilm 设备)留 Plan 2c:
    /// 需先 OpenSession + GetDeviceInfo 读 MTPExtension 再 mtpExtensionFallback 判定。
    /// 本 plan 对此类设备 throw needsInfoFallback。
    ///
    /// ⚠️ 不能在 open 的 MTPGlobalLock.sync 闭包内调用 close()(后者也加锁,串行队列不可重入会死锁);
    /// 故 P3 校验失败时用内联回滚(直接 release + close,不加锁)。
    func open() throws {
        try MTPGlobalLock.sync {
            guard handle == nil else { throw MTPError.alreadyOpen }

            var h: OpaquePointer?
            try checkLibusb(libusb_open(device, &h))
            guard let h else {
                throw MTPError.libusb(MTPUSBError(code: LIBUSB_ERROR_OTHER.rawValue))
            }
            self.handle = h

            // claim(对应 Go mtp.go:170)。Go 不检查返回;Swift 决定 claim 失败当致命错误(更严谨)。
            do {
                try checkLibusb(libusb_claim_interface(h, Int32(interfaceDescriptor.interfaceNumber)))
            } catch {
                // claim 失败:关闭已 open 的 handle,避免泄漏。
                libusb_close(h)
                self.handle = nil
                throw error
            }
            self.claimed = true

            // 接口串校验(P3 三星 CDC/ACM 补丁分支)。
            if interfaceDescriptor.interfaceStringIndex == 0 {
                // P4 分支:无接口串,需 GetDeviceInfo 兜底 → Plan 2c 补。
                self.rollbackOpenNoLock()
                throw MTPError.needsInfoFallback
            }
            // P3 分支:有接口串,含 MTP/CDC/ACM 之一才视为 MTP(对应 Go mtp.go:184-198)。
            let iface = try getStringDescriptorASCII(interfaceDescriptor.interfaceStringIndex)
            if !interfaceStringLooksLikeMTP(iface) {
                self.rollbackOpenNoLock()
                throw MTPError.noMTPInInterface
            }
        }
    }

    /// open 失败时的内联回滚(release + close),不加锁(已在 open 的锁内)。
    /// 避免在 MTPGlobalLock.sync 闭包内调用 close() 导致串行队列死锁。
    private func rollbackOpenNoLock() {
        guard let h = handle else { return }
        if claimed {
            libusb_release_interface(h, Int32(interfaceDescriptor.interfaceNumber))
            claimed = false
        }
        libusb_close(h)
        handle = nil
    }

    /// 读 USB 字符串描述符为 ASCII String(对应 Go usb.go:663)。
    /// 必须在 open 后(handle 非 nil)调用。
    private func getStringDescriptorASCII(_ index: UInt8) throws -> String {
        guard let h = handle else { throw MTPError.notOpen }
        var buf = [UInt8](repeating: 0, count: 1024)
        // libusb_get_string_descriptor_ascii 返回写入字节数(< 0 为错误)。
        let n = buf.withUnsafeMutableBufferPointer { ptr -> Int32 in
            // baseAddress 可空(空 buffer 不会发生,但解包防御)。
            guard let base = ptr.baseAddress else { return LIBUSB_ERROR_OTHER.rawValue }
            return libusb_get_string_descriptor_ascii(h, index, base, Int32(ptr.count))
        }
        try checkLibusb(n)
        // n 为实际写入字节数;按有效长度截断后 UTF-8 解码(遇 \0 自然截断)。
        let valid = Int(n)
        let decoded = String(decoding: buf.prefix(valid), as: UTF8.self)
        // C 字符串语义:在首个 \0 处截断(描述符可能含尾随 \0)。
        if let terminator = decoded.firstIndex(of: "\0") {
            return String(decoded[..<terminator])
        }
        return decoded
    }

    /// 关闭设备(对应 Go mtp.go:95-126)。幂等。
    /// Plan 2b:仅 release_interface + libusb_close(session 管理在 Plan 2c 会加 throw 路径)。
    func close() throws {
        // MTPGlobalLock.sync 是 rethrows:当前闭包不 throw,故无需 try(Plan 2c session 清理可 throw)。
        MTPGlobalLock.sync {
            guard let h = handle else { return }
            if claimed {
                libusb_release_interface(h, Int32(interfaceDescriptor.interfaceNumber))
                claimed = false
            }
            libusb_close(h)
            handle = nil
        }
    }
}

// MARK: - bulk 单包读写(Task 3)

extension MTPDevice {
    /// 发命令包。对照 Go mtp.go:291 sendReq。
    /// 构造 usbBulkContainer(12B 小端 header + params 小端 u32)经 sendEP 发出。
    /// Length = usbHeaderLength(12) + 4*params.count;Type=command;code/tid 由 request 填。
    ///
    /// ⚠️ buffer 生命周期:`withUnsafeMutableBufferPointer` 闭包限定,bulkTransfer 同步返回后即释放,
    /// 绝不让指针逃逸。bulk 调用点局部 `MTPGlobalLock.sync`(在 bulkTransfer 内)。
    func sendReq(_ request: MTPRequest) throws {
        guard let h = handle else { throw MTPError.notOpen }
        var buf: [UInt8] = []
        let length = UInt32(MTPConstants.usbHeaderLength + 4 * request.params.count)
        // 线序(小端):length u32 @0, type u16 @4, code u16 @6, tid u32 @8, 然后 params。
        buf.appendContentsOfLE(length)
        buf.appendContentsOfLE(ContainerType.command.rawValue)
        buf.appendContentsOfLE(request.code.rawValue)
        buf.appendContentsOfLE(request.transactionID)
        for p in request.params { buf.appendContentsOfLE(p) }
        try buf.withUnsafeMutableBufferPointer { ptr in
            guard let base = ptr.baseAddress else { throw MTPError.libusb(MTPUSBError(code: -99)) }
            _ = try bulkTransfer(h, endpoint: sendEP, buffer: base, length: ptr.count,
                                 timeout: UInt32(timeout))
        }
    }

    /// 读单包 + 解 header。对照 Go mtp.go:322 fetchPacket。
    /// 返回 (rest=去 header 的 payload, bytesRead=本次实际读字节, header)。
    ///
    /// ⚠️ rest 拷成值类型(`Array(buf[...])`),buf 出闭包后失效,故不持有指针。
    func fetchPacket() throws -> (rest: [UInt8], bytesRead: Int, header: MTPBulkHeaderParsed) {
        guard let h = handle else { throw MTPError.notOpen }
        var buf = [UInt8](repeating: 0, count: fetchMaxPacketSize())
        let n = try buf.withUnsafeMutableBufferPointer { ptr -> Int in
            guard let base = ptr.baseAddress else { throw MTPError.libusb(MTPUSBError(code: -99)) }
            return try bulkTransfer(h, endpoint: fetchEP, buffer: base, length: ptr.count,
                                    timeout: UInt32(timeout))
        }
        guard n >= MTPConstants.usbHeaderLength else {
            throw MTPError.syncError("fetchPacket read \(n) bytes < header \(MTPConstants.usbHeaderLength)")
        }
        let header = try parseBulkHeader(Array(buf[0..<MTPConstants.usbHeaderLength]))
        let rest = Array(buf[MTPConstants.usbHeaderLength..<n])
        return (rest, n, header)
    }

    /// fetch 端点 max packet size(通常 512)。对照 Go fetchMaxPacketSize。
    /// Plan 2c spike 用默认值;后续 plan 可从端点描述符 wMaxPacketSize 取(更精确)。
    func fetchMaxPacketSize() -> Int { 512 }
    /// send 端点 max packet size(Plan 2d bulkWrite/ZLP 判定用)。对照 Go sendMaxPacketSize。
    func sendMaxPacketSize() -> Int { 512 }
}

/// 小端编码辅助(私有)。向 [UInt8] 追加 u32/u16 的小端字节序。
private extension Array where Element == UInt8 {
    mutating func appendContentsOfLE(_ v: UInt32) {
        append(UInt8(v & 0xFF))
        append(UInt8((v >> 8) & 0xFF))
        append(UInt8((v >> 16) & 0xFF))
        append(UInt8((v >> 24) & 0xFF))
    }
    mutating func appendContentsOfLE(_ v: UInt16) {
        append(UInt8(v & 0xFF))
        append(UInt8((v >> 8) & 0xFF))
    }
}
