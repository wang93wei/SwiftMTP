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
    static let shared = DeviceManager()
    
    @Published var devices: [Device] = []
    @Published var selectedDevice: Device?
    @Published var isScanning: Bool = false
    @Published var connectionError: String?
    @Published var hasScannedOnce: Bool = false
    @Published var showManualRefreshButton: Bool = false
    
    private var scanTimer: Timer?
    // Cache device UUIDs by device index to maintain consistent IDs across scans
    private var deviceIdCache: [Int: UUID] = [:]
    // Track last successful scan to detect disconnections
    private var lastDeviceIds: Set<UUID> = []
    // Exponential backoff properties
    private var consecutiveFailures: Int = 0
    private var currentScanInterval: TimeInterval = 3.0
    private let minScanInterval: TimeInterval = 3.0
    private let maxScanInterval: TimeInterval = 30.0
    private let maxFailuresBeforeManualRefresh: Int = 3
    
    private init() {
        // Initialize Kalam
        Kalam_Init()
        startScanning()
    }
    
    deinit {
        stopScanning()
    }
    
    // MARK: - Public Methods
    
    func startScanning() {
        // Adaptive scanning frequency:
        // - Every 3 seconds when no device connected
        // - Every 5 seconds when device is connected (more stable)
        scanTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.scanDevices()
        }
        scanDevices()
    }
    
    func stopScanning() {
        scanTimer?.invalidate()
        scanTimer = nil
    }
    
    func scanDevices() {
        // Don't block scanning even if device is selected - we need to detect disconnections
        // But avoid concurrent scans
        guard !isScanning else { return }
        
        // Stop automatic scanning after max failures
        if consecutiveFailures >= maxFailuresBeforeManualRefresh {
            print("[DeviceManager] Max failures reached, stopping automatic scanning")
            stopScanning()
            return
        }
        
        print("[DeviceManager] Starting scan, current failures: \(consecutiveFailures), interval: \(currentScanInterval)s")
        
        // Set scanning flag on main thread
        DispatchQueue.main.async { [weak self] in
            self?.isScanning = true
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // Call Kalam_Scan via Go bridge
            guard let jsonPtr = Kalam_Scan() else {
                print("[DeviceManager] Kalam_Scan returned nil - no devices found")
                DispatchQueue.main.async {
                    self.handleDeviceDisconnection()
                    self.isScanning = false
                    self.hasScannedOnce = true
                    
                    // Stop automatic scanning after max failures
                    if self.consecutiveFailures >= self.maxFailuresBeforeManualRefresh {
                        print("[DeviceManager] Max failures reached, stopping automatic scanning")
                        self.stopScanning()
                    }
                }
                return
            }
            
            let jsonString = String(cString: jsonPtr)
            Kalam_FreeString(jsonPtr) // Important: Free memory allocated by C/Go
            
            guard let data = jsonString.data(using: .utf8) else {
                print("[DeviceManager] Failed to convert device JSON string to data")
                DispatchQueue.main.async {
                    self.handleDeviceDisconnection()
                    self.isScanning = false
                    self.hasScannedOnce = true
                    
                    // Stop automatic scanning after max failures
                    if self.consecutiveFailures >= self.maxFailuresBeforeManualRefresh {
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
                    
                    // Stop automatic scanning after max failures
                    if self.consecutiveFailures >= self.maxFailuresBeforeManualRefresh {
                        print("[DeviceManager] Max failures reached, stopping automatic scanning")
                        self.stopScanning()
                    }
                }
            }
        }
    }
    
    func selectDevice(_ device: Device) {
        selectedDevice = device
        connectionError = nil
    }
    
    func manualRefresh() {
        // Reset failure counter and scan interval
        consecutiveFailures = 0
        currentScanInterval = minScanInterval
        showManualRefreshButton = false
        
        // Restart automatic scanning
        startScanning()
        
        print("[DeviceManager] Manual refresh triggered - counters reset, automatic scanning restarted")
    }
    
    // MARK: - Private Methods
    
    private func updateDevices(_ newDevices: [Device]) {
        let newIds = Set(newDevices.map { $0.id })
        
        // Check if selected device is still connected
        if let selected = selectedDevice, !newIds.contains(selected.id) {
            // Device disconnected
            handleDeviceDisconnection()
        }
        
        // Update device list
        devices = newDevices
        lastDeviceIds = newIds
        
        // Reset failure counter and scan interval on successful device detection
        if !newDevices.isEmpty {
            consecutiveFailures = 0
            currentScanInterval = minScanInterval
            showManualRefreshButton = false
        }
        
        // Adaptive scanning frequency based on device connection state
        let previousInterval = scanTimer?.timeInterval ?? 3.0
        let newInterval: TimeInterval = newDevices.isEmpty ? currentScanInterval : 5.0
        
        // Update scanning interval if needed
        if abs(previousInterval - newInterval) > 0.5 {
            scanTimer?.invalidate()
            scanTimer = Timer.scheduledTimer(withTimeInterval: newInterval, repeats: true) { [weak self] _ in
                self?.scanDevices()
            }
            print("Scanning interval updated to \(newInterval)s (devices: \(newDevices.count))")
        }
        
        // Auto-select if only one device and none selected
        if selectedDevice == nil && newDevices.count == 1 {
            selectedDevice = newDevices.first
        }
    }
    
    private func handleDeviceDisconnection() {
        if selectedDevice != nil || !devices.isEmpty {
            // Clear everything
            devices = []
            selectedDevice = nil
            connectionError = L10n.MainWindow.deviceDisconnected
            
            // Clear file system cache
            FileSystemManager.shared.clearCache()
            
            // Post notification to reset UI
            NotificationCenter.default.post(name: NSNotification.Name("DeviceDisconnected"), object: nil)
            
            print("Device disconnected - UI reset")
        }
        
        // Increment failure counter
        consecutiveFailures += 1
        
        // Exponential backoff: interval = min(3 * 2^failures, maxInterval)
        let backoffInterval = min(minScanInterval * pow(2.0, Double(consecutiveFailures)), maxScanInterval)
        currentScanInterval = backoffInterval
        
        // Show manual refresh button after max failures
        if consecutiveFailures >= maxFailuresBeforeManualRefresh {
            showManualRefreshButton = true
        }
        
        print("Scan failed \(consecutiveFailures) times, next scan in \(backoffInterval)s")
    }
    
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
        
        let deviceId = deviceIdCache[kalamDevice.id] ?? UUID()
        deviceIdCache[kalamDevice.id] = deviceId
        
        return Device(
            id: deviceId,
            deviceIndex: kalamDevice.id,
            name: kalamDevice.name,
            manufacturer: kalamDevice.manufacturer,
            model: kalamDevice.model,
            serialNumber: "",
            batteryLevel: nil,
            storageInfo: storageInfos,
            mtpSupportInfo: mtpSupportInfo,
            isConnected: true
        )
    }
}
