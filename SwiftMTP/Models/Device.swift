//
//  Device.swift
//  SwiftMTP
//
//  Data model representing an MTP device
//

import Foundation

struct StorageInfo: Identifiable, Codable, Sendable {
    let id: UUID
    let storageID: MTPStorageID
    let maxCapacity: UInt64
    let freeSpace: UInt64
    let description: String

    /// Raw projection retained only for the not-yet-migrated transfer boundary.
    var storageId: UInt32 { storageID.rawValue }
    
    var usedSpace: UInt64 {
        maxCapacity - freeSpace
    }
    
    var usagePercentage: Double {
        guard maxCapacity > 0 else { return 0 }
        return Double(usedSpace) / Double(maxCapacity) * 100
    }
    
    init(
        id: UUID = UUID(),
        storageID: MTPStorageID,
        maxCapacity: UInt64,
        freeSpace: UInt64,
        description: String
    ) {
        self.id = id
        self.storageID = storageID
        self.maxCapacity = maxCapacity
        self.freeSpace = freeSpace
        self.description = description
    }

    init(
        id: UUID = UUID(),
        storageId: UInt32,
        maxCapacity: UInt64,
        freeSpace: UInt64,
        description: String
    ) {
        self.init(
            id: id,
            storageID: MTPStorageID(rawValue: storageId),
            maxCapacity: maxCapacity,
            freeSpace: freeSpace,
            description: description
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case storageID = "storageId"
        case maxCapacity
        case freeSpace
        case description
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        let rawStorageID = try container.decode(UInt32.self, forKey: .storageID)
        do {
            storageID = try MTPStorageID(validating: rawStorageID)
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .storageID,
                in: container,
                debugDescription: "MTP storage ID must be non-zero"
            )
        }
        maxCapacity = try container.decode(UInt64.self, forKey: .maxCapacity)
        freeSpace = try container.decode(UInt64.self, forKey: .freeSpace)
        description = try container.decode(String.self, forKey: .description)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(storageID.rawValue, forKey: .storageID)
        try container.encode(maxCapacity, forKey: .maxCapacity)
        try container.encode(freeSpace, forKey: .freeSpace)
        try container.encode(description, forKey: .description)
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
    let mtpIdentity: MTPDeviceIdentity
    let name: String
    let manufacturer: String
    let model: String
    let serialNumber: String
    let batteryLevel: Int?
    var storageInfo: [StorageInfo]
    var mtpSupportInfo: MTPSupportInfo?
    var isConnected: Bool
    
    init(id: UUID = UUID(), deviceIndex: Int, mtpIdentity: MTPDeviceIdentity,
         name: String, manufacturer: String,
         model: String, serialNumber: String, batteryLevel: Int?, 
         storageInfo: [StorageInfo] = [], mtpSupportInfo: MTPSupportInfo? = nil,
         isConnected: Bool = true) {
        self.id = id
        self.deviceIndex = deviceIndex
        self.mtpIdentity = mtpIdentity
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
    
    /// 用于 SwiftUI Preview 的示例设备
    static let preview = Device(
        deviceIndex: 0,
        mtpIdentity: MTPDeviceIdentity(
            providerKind: .go,
            deviceID: MTPDeviceID(rawValue: "go:1:1:18d1:4ee1")
        ),
        name: "Pixel 7",
        manufacturer: "Google",
        model: "Pixel 7",
        serialNumber: "ABC123",
        batteryLevel: nil,
        storageInfo: [
            StorageInfo(
                storageID: MTPStorageID(rawValue: 1),
                maxCapacity: 128_000_000_000,
                freeSpace: 32_000_000_000,
                description: "内部存储"
            )
        ],
        mtpSupportInfo: MTPSupportInfo(
            mtpVersion: "1.0",
            deviceVersion: "1.0",
            vendorExtension: "Google"
        )
    )
}
