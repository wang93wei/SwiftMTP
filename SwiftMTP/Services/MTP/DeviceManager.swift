//
//  DeviceManager.swift
//  SwiftMTP
//
//  Manages MTP device detection and connection using Kalam Kernel
//

import Foundation
import Combine

// Helper structs for JSON decoding from Kalam
struct KalamDevice: Codable {
    let id: Int
    let name: String
    let manufacturer: String
    let model: String
    let serialNumber: String
    let storage: [KalamStorage]
    let mtpSupport: KalamMTPSupport
}

struct KalamMTPSupport: Codable {
    let mtpVersion: String
    let deviceVersion: String
    let vendorExtension: String
}

struct KalamStorage: Codable {
    let id: UInt32
    let description: String
    let freeSpace: UInt64
    let maxCapacity: UInt64
}

class DeviceManager: ObservableObject {
    // MARK: - 单例
    
    static let shared = DeviceManager()
    
    // MARK: - 常量
    
    /// 最小扫描间隔（秒）- 无设备时
    private static let MinScanInterval: TimeInterval = 3.0
    
    /// 设备连接后的扫描间隔（秒）
    private static let ConnectedDeviceScanInterval: TimeInterval = 5.0
    
    /// 最大扫描间隔（秒）- 指数退避上限
    private static let MaxScanInterval: TimeInterval = 30.0
    
    /// 最大连续失败次数
    private static let MaxFailuresBeforeManualRefresh: Int = 3
    
    /// 根目录 ID（MTP 协议标准值）
    private static let RootDirectoryId: UInt32 = 0xFFFFFFFF
    
    // MARK: - 发布属性
    
    /// 设备列表
    @Published var devices: [Device] = []
    
    /// 当前选中的设备
    @Published var selectedDevice: Device?
    
    /// 是否正在扫描
    @Published var isScanning: Bool = false
    
    /// 连接错误信息
    @Published var connectionError: String?
    
    /// 是否已扫描过至少一次
    @Published var hasScannedOnce: Bool = false
    
    /// 是否显示手动刷新按钮
    @Published var showManualRefreshButton: Bool = false
    
    // MARK: - 私有属性
    
    /// 扫描定时器
    private var scanTimer: Timer?
    
    /// 设备 ID 缓存（使用NSCache实现自动内存管理）
    private let deviceIdCache = NSCache<NSNumber, UUIDWrapper>()
    
    /// 设备序列号缓存（使用NSCache实现自动内存管理）
    private let deviceSerialCache = NSCache<NSNumber, NSString>()
    
    /// UUID包装类（用于NSCache，因为NSCache要求对象类型必须是类）
    private class UUIDWrapper: NSObject {
        let uuid: UUID
        init(_ uuid: UUID) {
            self.uuid = uuid
        }
    }
    
    /// 上次成功扫描的设备序列号集合（用于检测设备断开）
    private var lastDeviceSerials: Set<String> = []
    
    /// 连续失败次数（用于指数退避）
    private var consecutiveFailures: Int = 0
    
    /// 当前扫描间隔（秒）
    private var currentScanInterval: TimeInterval = MinScanInterval
    
    private init() {
        // 初始化 Kalam 内核
        Kalam_Init()
        
        // 配置设备ID缓存
        deviceIdCache.countLimit = 100  // 最多缓存100个设备
        deviceIdCache.totalCostLimit = 10 * 1024 * 1024  // 10MB限制
        
        // 配置设备序列号缓存
        deviceSerialCache.countLimit = 100  // 最多缓存100个设备
        deviceSerialCache.totalCostLimit = 10 * 1024  // 10KB限制
        
        startScanning()
    }
    
    deinit {
        stopScanning()
    }
    
    // MARK: - 公共方法
    
    /// 开始扫描设备
    /// 使用自适应扫描频率：
    /// - 无设备时：每 3 秒扫描一次
    /// - 有设备时：每 5 秒扫描一次（更稳定）
    func startScanning() {
        scanTimer = Timer.scheduledTimer(withTimeInterval: DeviceManager.MinScanInterval, repeats: true) { [weak self] _ in
            self?.scanDevices()
        }
        scanDevices()
    }
    
    /// 停止扫描设备
    func stopScanning() {
        scanTimer?.invalidate()
        scanTimer = nil
    }
    
    /// 扫描设备
    /// 检测设备连接和断开，使用指数退避策略减少失败时的扫描频率
    func scanDevices() {
        // 避免并发扫描
        guard !isScanning else { return }
        
        // 达到最大失败次数后停止自动扫描
        if consecutiveFailures >= DeviceManager.MaxFailuresBeforeManualRefresh {
            print("[DeviceManager] Max failures reached, stopping automatic scanning")
            stopScanning()
            return
        }
        
        print("[DeviceManager] Starting scan, current failures: \(consecutiveFailures), interval: \(currentScanInterval)s")
        
        // 在主线程上设置扫描标志
        DispatchQueue.main.async { [weak self] in
            self?.isScanning = true
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // 调用 Kalam_Scan 通过 Go 桥接
            guard let jsonPtr = Kalam_Scan() else {
                print("[DeviceManager] Kalam_Scan returned nil - no devices found")
                DispatchQueue.main.async {
                    self.handleDeviceDisconnection()
                    self.isScanning = false
                    self.hasScannedOnce = true
                    
                    // 达到最大失败次数后停止自动扫描
                    if self.consecutiveFailures >= DeviceManager.MaxFailuresBeforeManualRefresh {
                        print("[DeviceManager] Max failures reached, stopping automatic scanning")
                        self.stopScanning()
                    }
                }
                return
            }
            
            // 使用 defer 确保内存总是被释放
            defer {
                Kalam_FreeString(jsonPtr)
            }
            
            let jsonString = String(cString: jsonPtr)
            
            guard let data = jsonString.data(using: .utf8) else {
                print("[DeviceManager] Failed to convert device JSON string to data")
                DispatchQueue.main.async {
                    self.handleDeviceDisconnection()
                    self.isScanning = false
                    self.hasScannedOnce = true
                    
                    // 达到最大失败次数后停止自动扫描
                    if self.consecutiveFailures >= DeviceManager.MaxFailuresBeforeManualRefresh {
                        print("[DeviceManager] Max failures reached, stopping automatic scanning")
                        self.stopScanning()
                    }
                }
                return
            }
            
            do {
                let kalamDevices = try JSONDecoder().decode([KalamDevice].self, from: data)
                let newDevices = kalamDevices.map { self.mapToDevice($0) }
                
                print("[DeviceManager] Successfully found \(newDevices.count) device(s)")
                
                DispatchQueue.main.async {
                    self.updateDevices(newDevices)
                    self.isScanning = false
                    self.hasScannedOnce = true
                }
            } catch {
                print("[DeviceManager] Failed to decode devices JSON: \(error)")
                DispatchQueue.main.async {
                    self.handleDeviceDisconnection()
                    self.isScanning = false
                    self.hasScannedOnce = true
                    
                    // 达到最大失败次数后停止自动扫描
                    if self.consecutiveFailures >= DeviceManager.MaxFailuresBeforeManualRefresh {
                        print("[DeviceManager] Max failures reached, stopping automatic scanning")
                        self.stopScanning()
                    }
                }
            }
        }
    }
    
    /// 选择设备
    /// - Parameter device: 要选择的设备
    func selectDevice(_ device: Device) {
        selectedDevice = device
        connectionError = nil
    }
    
    /// 手动刷新设备列表
    /// 重置失败计数和扫描间隔，重新开始自动扫描
    func manualRefresh() {
        // 重置失败计数和扫描间隔
        consecutiveFailures = 0
        currentScanInterval = DeviceManager.MinScanInterval
        showManualRefreshButton = false
        
        // 重新开始自动扫描
        startScanning()
        
        print("[DeviceManager] Manual refresh triggered - counters reset, automatic scanning restarted")
    }
    
    // MARK: - 私有方法
    
    /// 更新设备列表
    /// - Parameter newDevices: 新的设备列表
    private func updateDevices(_ newDevices: [Device]) {
        let newSerials = Set(newDevices.map { $0.serialNumber })
        
        // 检查选中的设备是否仍然连接（使用序列号而非 UUID）
        if let selected = selectedDevice, !selected.serialNumber.isEmpty && !newSerials.contains(selected.serialNumber) {
            // 设备已断开
            handleDeviceDisconnection()
        }
        
        // 更新设备列表
        devices = newDevices
        lastDeviceSerials = newSerials
        
        // 成功检测到设备时重置失败计数和扫描间隔
        if !newDevices.isEmpty {
            consecutiveFailures = 0
            currentScanInterval = DeviceManager.MinScanInterval
            showManualRefreshButton = false
        }
        
        // 根据设备连接状态自适应扫描频率
        let previousInterval = scanTimer?.timeInterval ?? DeviceManager.MinScanInterval
        let newInterval: TimeInterval = newDevices.isEmpty ? currentScanInterval : DeviceManager.ConnectedDeviceScanInterval
        
        // 如果需要，更新扫描间隔
        if abs(previousInterval - newInterval) > 0.5 {
            scanTimer?.invalidate()
            scanTimer = Timer.scheduledTimer(withTimeInterval: newInterval, repeats: true) { [weak self] _ in
                self?.scanDevices()
            }
            print("[DeviceManager] Scanning interval updated to \(newInterval)s (devices: \(newDevices.count))")
        }
        
        // 如果只有一个设备且未选择，自动选择
        if selectedDevice == nil && newDevices.count == 1 {
            selectedDevice = newDevices.first
        }
    }
    
    /// 处理设备断开
    /// 清除所有设备相关状态，取消正在进行的传输任务
    private func handleDeviceDisconnection() {
        if selectedDevice != nil || !devices.isEmpty {
            // 取消所有活跃的传输任务
            FileTransferManager.shared.cancelAllTasks()
            
            // 清除所有内容
            devices = []
            selectedDevice = nil
            connectionError = L10n.MainWindow.deviceDisconnected
            
            // 清除文件系统缓存
            FileSystemManager.shared.clearCache()
            
            // 发送通知以重置 UI
            NotificationCenter.default.post(name: NSNotification.Name("DeviceDisconnected"), object: nil)
            
            print("[DeviceManager] Device disconnected - UI reset and tasks cancelled")
        }
        
        // 增加失败计数
        consecutiveFailures += 1
        
        // 指数退避：interval = min(3 * 2^failures, maxInterval)
        let backoffInterval = min(DeviceManager.MinScanInterval * pow(2.0, Double(consecutiveFailures)), DeviceManager.MaxScanInterval)
        currentScanInterval = backoffInterval
        
        // 达到最大失败次数后显示手动刷新按钮
        if consecutiveFailures >= DeviceManager.MaxFailuresBeforeManualRefresh {
            showManualRefreshButton = true
        }
        
        print("[DeviceManager] Scan failed \(consecutiveFailures) times, next scan in \(backoffInterval)s")
    }
    
    /// 将 Kalam 设备映射到应用设备模型
    /// - Parameter kalamDevice: Kalam 设备
    /// - Returns: 应用设备模型
    private func mapToDevice(_ kalamDevice: KalamDevice) -> Device {
        let storageInfos = kalamDevice.storage.map { storage in
            StorageInfo(
                storageId: storage.id,
                maxCapacity: storage.maxCapacity,
                freeSpace: storage.freeSpace,
                description: storage.description
            )
        }
        
        let mtpSupportInfo = MTPSupportInfo(
            mtpVersion: kalamDevice.mtpSupport.mtpVersion,
            deviceVersion: kalamDevice.mtpSupport.deviceVersion,
            vendorExtension: kalamDevice.mtpSupport.vendorExtension
        )
        
        // 使用缓存的 UUID 或生成新的（NSCache是线程安全的）
        let deviceKey = NSNumber(value: kalamDevice.id)
        let deviceIdWrapper = deviceIdCache.object(forKey: deviceKey) ?? UUIDWrapper(UUID())
        deviceIdCache.setObject(deviceIdWrapper, forKey: deviceKey)
        let deviceId = deviceIdWrapper.uuid
        
        // 缓存序列号用于设备唯一标识（NSCache是线程安全的）
        deviceSerialCache.setObject(NSString(string: kalamDevice.serialNumber), forKey: deviceKey)
        
        return Device(
            id: deviceId,
            deviceIndex: kalamDevice.id,
            name: kalamDevice.name,
            manufacturer: kalamDevice.manufacturer,
            model: kalamDevice.model,
            serialNumber: kalamDevice.serialNumber,
            batteryLevel: nil,
            storageInfo: storageInfos,
            mtpSupportInfo: mtpSupportInfo,
            isConnected: true
        )
    }
}
