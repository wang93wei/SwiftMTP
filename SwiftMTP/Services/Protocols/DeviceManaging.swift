//
//  DeviceManaging.swift
//  SwiftMTP
//
//  Protocol for device management operations
//

import Foundation
import Combine

/// Protocol defining device management operations
/// Provides abstraction for testing and dependency injection
@MainActor
protocol DeviceManaging: ObservableObject {
    // MARK: - Published Properties
    
    /// List of detected devices
    var devices: [Device] { get set }
    
    /// Currently selected device
    var selectedDevice: Device? { get set }
    
    /// Whether device scanning is in progress
    var isScanning: Bool { get set }
    
    /// Connection error message
    var connectionError: String? { get set }
    
    /// Whether at least one scan has been performed
    var hasScannedOnce: Bool { get set }
    
    /// Whether to show manual refresh button
    var showManualRefreshButton: Bool { get set }
    
    // MARK: - Public Methods
    
    /// Update scan interval from user settings
    func updateScanInterval()
    
    /// Start scanning for devices
    func startScanning()
    
    /// Stop scanning for devices
    func stopScanning()
    
    /// Perform a device scan
    func scanDevices()
    
    /// Select a device
    /// - Parameter device: The device to select
    func selectDevice(_ device: Device)
    
    /// Manually refresh the device list
    func manualRefresh()
}