//
//  DeviceManager.swift
//  SwiftMTP
//
//  Manages MTP device detection and connection using Kalam Kernel
//

import Foundation
import Combine

@MainActor
class DeviceManager: ObservableObject {
    // MARK: - Singleton

    static let shared = DeviceManager(runtime: MTPProviderRuntime.shared)

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

    /// Recoverable per-device or per-storage failures from the last successful scan.
    @Published private(set) var scanFailures: [MTPScanFailure] = []

    // MARK: - 私有属性

    /// User configured scan interval in seconds
    private var userScanInterval: TimeInterval {
        let interval = UserDefaults.standard.double(forKey: AppConfiguration.scanIntervalKey)
        return interval > 0 ? interval : AppConfiguration.defaultScanInterval
    }

    /// Scan task for AsyncStream-based periodic scanning
    private var scanTask: Task<Void, Never>?
    
    /// In-flight detached scan operation task
    private var scanOperationTask: Task<Void, Never>?
    
    /// Whether app termination cleanup has started
    private var isShuttingDown: Bool = false
    
    private let runtime: any MTPProviderRuntimeProtocol
    private var appIDsByIdentity: [MTPDeviceIdentity: UUID] = [:]
    
    /// Consecutive failure count (for exponential backoff)
    private var consecutiveFailures: Int = 0
    
    /// Current scan interval in seconds
    private var currentScanInterval: TimeInterval = AppConfiguration.defaultScanInterval
    
    init(
        runtime: any MTPProviderRuntimeProtocol,
        startsScanning: Bool = true
    ) {
        self.runtime = runtime
        // Initialize scan interval to user configured value
        currentScanInterval = userScanInterval
        if startsScanning {
            startScanning()
        }
    }
    
    deinit {
        // Task cleanup will be handled by automatic deallocation
        // Cancel the scan task to stop async operations
        scanTask?.cancel()
        scanOperationTask?.cancel()
    }
    
    // MARK: - 公共方法
    
    /// 更新扫描间隔
    /// 当用户更改设置时调用此方法以应用新的扫描间隔
    func updateScanInterval() {
        // 重新启动扫描以应用新的间隔
        if scanTask != nil {
            stopScanning()
            startScanning()
        }
    }

    /// Start scanning for devices
    /// Uses user configured scan interval with AsyncStream
    func startScanning() {
        guard !isShuttingDown else { return }
        guard scanTask == nil else { return }
        
        let interval = TimeInterval(userScanInterval)

        // Create an AsyncStream that emits values at regular intervals
        let timerStream = AsyncStream.makeTimer(interval: interval)

        scanTask = Task {
            for await _ in timerStream {
                // Check if task is cancelled
                if Task.isCancelled {
                    break
                }
                scanDevices()
            }
        }

        // Perform initial scan immediately
        scanDevices()
    }

    /// 停止扫描设备
    func stopScanning() {
        scanTask?.cancel()
        scanTask = nil
        scanOperationTask?.cancel()
        scanOperationTask = nil
    }
    
    /// Prepare manager for application termination.
    /// Stops periodic and in-flight scans before native cleanup begins.
    func prepareForTermination() {
        isShuttingDown = true
        stopScanning()
        isScanning = false
    }
    
    /// Scan for devices
    /// Detects device connection and disconnection, uses exponential backoff strategy to reduce scan frequency on failures
    func scanDevices() {
        _ = beginScan()
    }

    /// Starts a scan and suspends until its published state has been updated.
    /// Tests use this seam instead of polling wall-clock time.
    func scanDevicesAndWait() async {
        guard let task = beginScan() else {
            return
        }
        await task.value
    }

    private func beginScan() -> Task<Void, Never>? {
        // Avoid concurrent scanning
        guard !isScanning, !isShuttingDown else { return nil }
        
        // Stop automatic scanning after reaching max consecutive failures
        if consecutiveFailures >= AppConfiguration.maxFailuresBeforeManualRefresh {
            print("[DeviceManager] Max failures reached, stopping automatic scanning")
            stopScanning()
            return nil
        }
        
        let actualInterval = userScanInterval
        print("[DeviceManager] Starting scan, current failures: \(consecutiveFailures), interval: \(actualInterval)s")
        
        // Set scanning flag on main thread
        isScanning = true
        
        let task = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let shouldContinue = await MainActor.run { !self.isShuttingDown && !Task.isCancelled }
            guard shouldContinue else { return }
            
            do {
                let result = try self.runtime.scanDevices()
                await self.applySuccessfulScan(result)
            } catch {
                print("[DeviceManager] Typed device scan failed: \(error)")
                await self.applyFailedScan(error)
            }
        }
        scanOperationTask = task
        return task
    }
    
    /// 选择设备
    /// - Parameter device: 要选择的设备
    func selectDevice(_ device: Device) {
        do {
            try runtime.coordinator.selectDevice(device.id)
            selectedDevice = device
            connectionError = nil
        } catch {
            connectionError = String(describing: error)
        }
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
        let newIdentities = Set(newDevices.map(\.mtpIdentity))

        if let selected = selectedDevice,
           !newIdentities.contains(selected.mtpIdentity) {
            handleConfirmedDisconnection()
        }
        
        // Update device list
        devices = newDevices
        
                // Check if scan interval needs to be updated (when user settings change)
                // Only restart if the interval has actually changed
                let newInterval = userScanInterval
                if abs(newInterval - currentScanInterval) > 0.5 {
                    print("[DeviceManager] Scan interval changed from \(currentScanInterval)s to \(newInterval)s, restarting scanning")
                    currentScanInterval = newInterval
                    stopScanning()
                    startScanning()
                }        
        // Auto-select if only one device and none selected
        if selectedDevice == nil && newDevices.count == 1 {
            if let device = newDevices.first {
                selectDevice(device)
            }
        }
    }
    
    /// Clears device state only after a successful disappearance or explicit disconnect.
    private func handleConfirmedDisconnection() {
        if selectedDevice != nil || !devices.isEmpty {
            // Cancel all active transfer tasks
            FileTransferManager.shared.cancelAllTasks()
            runtime.coordinator.close()

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
    }

    private func recordScanFailure() {
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

    private func applySuccessfulScan(_ result: MTPScanResult) {
        guard !isShuttingDown else {
            finishScan()
            return
        }

        do {
            var newDevices = try result.snapshots.map { snapshot in
                let device = mapToDevice(snapshot)
                try runtime.coordinator.register(
                    appDeviceID: device.id,
                    snapshot: snapshot,
                    providerKind: runtime.providerKind
                )
                return device
            }
            let scannedIdentities = Set(newDevices.map(\.mtpIdentity))
            let inconclusiveIdentities = Set(
                result.failures
                    .filter { $0.error != .disconnected }
                    .map {
                        MTPDeviceIdentity(
                            providerKind: runtime.providerKind,
                            deviceID: $0.deviceID
                        )
                    }
            )
            newDevices.append(
                contentsOf: devices.filter {
                    inconclusiveIdentities.contains($0.mtpIdentity)
                        && !scannedIdentities.contains($0.mtpIdentity)
                }
            )
            print("[DeviceManager] Successfully found \(newDevices.count) device(s)")
            scanFailures = result.failures
            connectionError = nil
            consecutiveFailures = 0
            currentScanInterval = userScanInterval
            showManualRefreshButton = false
            updateDevices(newDevices)
        } catch {
            applyFailedScan(error)
            return
        }
        finishScan()
    }

    private func applyFailedScan(_ error: Error) {
        guard !isShuttingDown else {
            finishScan()
            return
        }

        if let coreError = error as? MTPCoreError,
           case .disconnected = coreError {
            handleConfirmedDisconnection()
        } else {
            connectionError = String(describing: error)
        }
        recordScanFailure()
        finishScan()

        if consecutiveFailures >= AppConfiguration.maxFailuresBeforeManualRefresh {
            print("[DeviceManager] Max failures reached, stopping automatic scanning")
            stopScanning()
        }
    }

    private func finishScan() {
        isScanning = false
        hasScannedOnce = true
        scanOperationTask = nil
    }
    
    /// Map a typed provider snapshot to the existing application model.
    /// - Returns: Application device model
    private func mapToDevice(_ snapshot: MTPDeviceSnapshot) -> Device {
        let identity = MTPDeviceIdentity(
            providerKind: runtime.providerKind,
            deviceID: snapshot.deviceID
        )
        let storageInfos = snapshot.storages.map { storage in
            StorageInfo(
                storageID: storage.id,
                maxCapacity: storage.maxCapacity,
                freeSpace: storage.freeSpace,
                description: storage.description
            )
        }
        let deviceID = appIDsByIdentity[identity] ?? UUID()
        appIDsByIdentity[identity] = deviceID
        let legacyIndex = Int(snapshot.deviceID.rawValue.split(separator: ":").last ?? "") ?? 0

        return Device(
            id: deviceID,
            deviceIndex: legacyIndex,
            mtpIdentity: identity,
            name: snapshot.name,
            manufacturer: snapshot.manufacturer,
            model: snapshot.model,
            serialNumber: "",
            batteryLevel: nil,
            storageInfo: storageInfos,
            mtpSupportInfo: nil,
            isConnected: true
        )
    }
}

// MARK: - AsyncStream Extensions

extension AsyncStream where Element == Void {
    /// Creates an AsyncStream that emits values at regular intervals
    /// - Parameter interval: The time interval between emissions
    /// - Returns: An AsyncStream that emits Void at the specified interval
    static func makeTimer(interval: TimeInterval) -> AsyncStream<Void> {
        return AsyncStream { continuation in
            let timerTask = Task {
                while !Task.isCancelled {
                    continuation.yield()
                    try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                }
                continuation.finish()
            }
            
            continuation.onTermination = { _ in
                timerTask.cancel()
            }
        }
    }
}
