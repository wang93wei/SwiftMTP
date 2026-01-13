//
//  Device.swift
//  SwiftMTP
//
//  Data model representing an MTP device
//

import Foundation

struct StorageInfo: Identifiable, Codable, Sendable {
    let id: UUID
    let storageId: UInt32
    let maxCapacity: UInt64
    let freeSpace: UInt64
    let description: String
    
    var usedSpace: UInt64 {
        maxCapacity - freeSpace
    }
    
    var usagePercentage: Double {
        guard maxCapacity > 0 else { return 0 }
        return Double(usedSpace) / Double(maxCapacity) * 100
    }
    
    init(id: UUID = UUID(), storageId: UInt32, maxCapacity: UInt64, freeSpace: UInt64, description: String) {
        self.id = id
        self.storageId = storageId
        self.maxCapacity = maxCapacity
        self.freeSpace = freeSpace
        self.description = description
    }
}

struct MTPSupportInfo: Identifiable, Codable, Sendable {
    let id: UUID
    let mtpVersion: String
    let deviceVersion: String
    let vendorExtension: String
    
    init(id: UUID = UUID(), mtpVersion: String, deviceVersion: String, vendorExtension: String) {
        self.id = id
        self.mtpVersion = mtpVersion
        self.deviceVersion = deviceVersion
        self.vendorExtension = vendorExtension
    }
}

struct Device: Identifiable, Hashable, Sendable {
    let id: UUID
    let deviceIndex: Int
    let name: String
    let manufacturer: String
    let model: String
    let serialNumber: String
    let batteryLevel: Int?
    var storageInfo: [StorageInfo]
    var mtpSupportInfo: MTPSupportInfo?
    var isConnected: Bool
    
    init(id: UUID = UUID(), deviceIndex: Int, name: String, manufacturer: String, 
         model: String, serialNumber: String, batteryLevel: Int?, 
         storageInfo: [StorageInfo] = [], mtpSupportInfo: MTPSupportInfo? = nil,
         isConnected: Bool = true) {
        self.id = id
        self.deviceIndex = deviceIndex
        self.name = name
        self.manufacturer = manufacturer
        self.model = model
        self.serialNumber = serialNumber
        self.batteryLevel = batteryLevel
        self.storageInfo = storageInfo
        self.mtpSupportInfo = mtpSupportInfo
        self.isConnected = isConnected
    }
    
    // Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: Device, rhs: Device) -> Bool {
        lhs.id == rhs.id
    }
    
    var displayName: String {
        if !name.isEmpty && name != "Unknown Device" {
            return name
        }
        return "\(manufacturer) \(model)"
    }
    
    var displayModel: String {
        // If name already contains the model info, don't repeat it
        if !name.isEmpty && name != "Unknown Device" {
            // If name contains manufacturer, just return model
            if name.lowercased().contains(manufacturer.lowercased()) {
                return model
            }
            // Otherwise return manufacturer + model
            return "\(manufacturer) \(model)"
        }
        // If using fallback displayName, just show manufacturer
        return manufacturer
    }
    
    var totalCapacity: UInt64 {
        storageInfo.reduce(0) { $0 + $1.maxCapacity }
    }
    
    var totalFreeSpace: UInt64 {
        storageInfo.reduce(0) { $0 + $1.freeSpace }
    }
}
