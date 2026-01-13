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

@MainActor
class DeviceManager: ObservableObject, DeviceManaging {
    // MARK: - Singleton
    
    static let shared = DeviceManager()
    
    // MARK: - Constants
    
    /// Default scan interval in seconds
    private static let DefaultScanInterval: TimeInterval = 3.0
    
    /// Scan interval when device is connected (seconds)
    private static let ConnectedDeviceScanInterval: TimeInterval = 5.0
    
    /// Maximum scan interval for exponential backoff (seconds)
    private static let MaxScanInterval: TimeInterval = 30.0
    
    /// Maximum consecutive failures before stopping automatic scan
    private static let MaxFailuresBeforeManualRefresh: Int = 3
    
    /// Root directory ID (MTP protocol standard value)
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
    
    /// User configured scan interval in seconds
    private var userScanInterval: TimeInterval {
        let interval = UserDefaults.standard.double(forKey: AppConfiguration.scanIntervalKey)
        return interval > 0 ? interval : AppConfiguration.defaultScanInterval
    }
    
    /// Scan timer
    private var scanTimer: Timer?
    
    /// Device ID cache (using NSCache for automatic memory management)
    private let deviceIdCache = NSCache<NSNumber, UUIDWrapper>()
    
    /// Device serial cache (using NSCache for automatic memory management)
    private let deviceSerialCache = NSCache<NSNumber, NSString>()
    
    /// UUID wrapper class (for NSCache, as NSCache requires object types to be classes)
    private class UUIDWrapper: NSObject {
        let uuid: UUID
        init(_ uuid: UUID) {
            self.uuid = uuid
        }
    }
    
    /// Last successful scan device serial set (for detecting device disconnection)
    private var lastDeviceSerials: Set<String> = []
    
    /// Consecutive failure count (for exponential backoff)
    private var consecutiveFailures: Int = 0
    
    /// Current scan interval in seconds
    private var currentScanInterval: TimeInterval = AppConfiguration.defaultScanInterval
    
    private init() {
        // Initialize Kalam kernel
        Kalam_Init()
        
        // Configure device ID cache
        deviceIdCache.countLimit = AppConfiguration.deviceCacheCountLimit
        deviceIdCache.totalCostLimit = AppConfiguration.deviceCacheTotalCostLimit
        
        // Configure device serial cache
        deviceSerialCache.countLimit = AppConfiguration.deviceCacheCountLimit
        deviceSerialCache.totalCostLimit = AppConfiguration.deviceSerialCacheTotalCostLimit
        
        // Initialize scan interval to user configured value
        currentScanInterval = userScanInterval
        
        startScanning()
    }
    
    deinit {
        // Timer cleanup will be handled by automatic deallocation
        // No manual cleanup needed as Timer will be released with the instance
    }
    
    // MARK: - 公共方法
    
    /// 更新扫描间隔
    /// 当用户更改设置时调用此方法以应用新的扫描间隔
    func updateScanInterval() {
        // 重新启动扫描以应用新的间隔
        if scanTimer != nil {
            stopScanning()
            startScanning()
        }
    }
    
    /// Start scanning for devices
    /// Uses user configured scan interval
    func startScanning() {
        let interval = TimeInterval(userScanInterval)
        scanTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.scanDevices()
            }
        }
        scanDevices()
    }
    
    /// 停止扫描设备
    func stopScanning() {
        scanTimer?.invalidate()
        scanTimer = nil
    }
    
    /// Scan for devices
    /// Detects device connection and disconnection, uses exponential backoff strategy to reduce scan frequency on failures
    func scanDevices() {
        // Avoid concurrent scanning
        guard !isScanning else { return }
        
        // Stop automatic scanning after reaching max consecutive failures
        if consecutiveFailures >= AppConfiguration.maxFailuresBeforeManualRefresh {
            print("[DeviceManager] Max failures reached, stopping automatic scanning")
            stopScanning()
            return
        }
        
        let actualInterval = scanTimer?.timeInterval ?? userScanInterval
        print("[DeviceManager] Starting scan, current failures: \(consecutiveFailures), interval: \(actualInterval)s")
        
        // Set scanning flag on main thread
        isScanning = true
        
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            
            // Call Kalam_Scan through Go bridge
            guard let jsonPtr = Kalam_Scan() else {
                print("[DeviceManager] Kalam_Scan returned nil - no devices found")
                await MainActor.run {
                    self.handleDeviceDisconnection()
                    self.isScanning = false
                    self.hasScannedOnce = true
                    
                    // Stop automatic scanning after reaching max consecutive failures
                    if self.consecutiveFailures >= AppConfiguration.maxFailuresBeforeManualRefresh {
                        print("[DeviceManager] Max failures reached, stopping automatic scanning")
                        self.stopScanning()
                    }
                }
                return
            }
            
            // Use defer to ensure memory is always freed
            defer {
                Kalam_FreeString(jsonPtr)
            }
            
            let jsonString = String(cString: jsonPtr)
            
            guard let data = jsonString.data(using: .utf8) else {
                print("[DeviceManager] Failed to convert device JSON string to data")
                await MainActor.run {
                    self.handleDeviceDisconnection()
                    self.isScanning = false
                    self.hasScannedOnce = true
                    
                    // Stop automatic scanning after reaching max consecutive failures
                    if self.consecutiveFailures >= AppConfiguration.maxFailuresBeforeManualRefresh {
                        print("[DeviceManager] Max failures reached, stopping automatic scanning")
                        self.stopScanning()
                    }
                }
                return
            }
            
            do {
                let kalamDevices = try JSONDecoder().decode([KalamDevice].self, from: data)
                
                // Map devices on MainActor since mapToDevice is MainActor isolated
                let newDevices = await MainActor.run {
                    return kalamDevices.map { self.mapToDevice($0) }
                }
                
                print("[DeviceManager] Successfully found \(newDevices.count) device(s)")
                
                await MainActor.run {
                    self.updateDevices(newDevices)
                    self.isScanning = false
                    self.hasScannedOnce = true
                }
            } catch {
                print("[DeviceManager] Failed to decode devices JSON: \(error)")
                await MainActor.run {
                    self.handleDeviceDisconnection()
                    self.isScanning = false
                    self.hasScannedOnce = true
                    
                    // Stop automatic scanning after reaching max consecutive failures
                    if self.consecutiveFailures >= AppConfiguration.maxFailuresBeforeManualRefresh {
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
    
    /// Manually refresh device list
    /// Resets failure count and scan interval, restarts automatic scanning
    func manualRefresh() {
        // Reset failure count and scan interval
        consecutiveFailures = 0
        currentScanInterval = userScanInterval
        showManualRefreshButton = false
        
        // Restart automatic scanning
        startScanning()
        
        print("[DeviceManager] Manual refresh triggered - counters reset, automatic scanning restarted")
    }
    
    // MARK: - 私有方法
    
    /// Update device list
    /// - Parameter newDevices: New device list
    private func updateDevices(_ newDevices: [Device]) {
        let newSerials = Set(newDevices.map { $0.serialNumber })
        
        // Check if selected device is still connected (using serial number instead of UUID)
        if let selected = selectedDevice, !selected.serialNumber.isEmpty && !newSerials.contains(selected.serialNumber) {
            // Device disconnected
            handleDeviceDisconnection()
        }
        
        // Update device list
        devices = newDevices
        lastDeviceSerials = newSerials
        
        // Reset failure count when devices are successfully detected
        if !newDevices.isEmpty {
            consecutiveFailures = 0
            currentScanInterval = userScanInterval
            showManualRefreshButton = false
        }
        
        // Check if scan interval needs to be updated (when user settings change)
        let previousInterval = scanTimer?.timeInterval ?? userScanInterval
        let newInterval = userScanInterval
        
        // Update scan interval if it differs from user settings
        if abs(previousInterval - newInterval) > 0.5 {
            scanTimer?.invalidate()
            scanTimer = Timer.scheduledTimer(withTimeInterval: newInterval, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.scanDevices()
                }
            }
            print("[DeviceManager] Scanning interval updated to \(newInterval)s")
        }
        
        // Auto-select if only one device and none selected
        if selectedDevice == nil && newDevices.count == 1 {
            selectedDevice = newDevices.first
        }
    }
    
    /// Handle device disconnection
    /// Clears all device-related state, cancels active transfer tasks
    private func handleDeviceDisconnection() {
        if selectedDevice != nil || !devices.isEmpty {
            // Cancel all active transfer tasks
            FileTransferManager.shared.cancelAllTasks()

            // Clear all content
            devices = []
            selectedDevice = nil
            connectionError = L10n.MainWindow.deviceDisconnected

            // Clear file system cache
            Task {
                await FileSystemManager.shared.clearCache()
            }

            // Send notification to reset UI
            NotificationCenter.default.post(name: NSNotification.Name("DeviceDisconnected"), object: nil)

            print("[DeviceManager] Device disconnected - UI reset and tasks cancelled")
        }
        
        // Increment failure count
        consecutiveFailures += 1
        
        // Exponential backoff: interval = min(3 * 2^failures, maxInterval)
        let backoffInterval = min(AppConfiguration.defaultScanInterval * pow(2.0, Double(consecutiveFailures)), AppConfiguration.maxScanInterval)
        currentScanInterval = backoffInterval
        
        // Show manual refresh button after reaching max consecutive failures
        if consecutiveFailures >= AppConfiguration.maxFailuresBeforeManualRefresh {
            showManualRefreshButton = true
        }
        
        print("[DeviceManager] Scan failed \(consecutiveFailures) times, next scan in \(backoffInterval)s")
    }
    
    /// Map Kalam device to application device model
    /// - Parameter kalamDevice: Kalam device
    /// - Returns: Application device model
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
        
        // Use cached UUID or generate new one (NSCache is thread-safe)
        let deviceKey = NSNumber(value: kalamDevice.id)
        let deviceIdWrapper = deviceIdCache.object(forKey: deviceKey) ?? UUIDWrapper(UUID())
        deviceIdCache.setObject(deviceIdWrapper, forKey: deviceKey)
        let deviceId = deviceIdWrapper.uuid
        
        // Cache serial number for device unique identification (NSCache is thread-safe)
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
