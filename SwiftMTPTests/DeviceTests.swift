//
//  DeviceTests.swift
//  SwiftMTPTests
//
//  Unit tests for Device, StorageInfo, and MTPSupportInfo models
//

import XCTest
@testable import SwiftMTP

final class DeviceTests: XCTestCase {
    
    // MARK: - StorageInfo Tests
    
    func testStorageInfoInitialization() {
        let storageInfo = StorageInfo(
            storageId: 1,
            maxCapacity: 64_000_000_000,
            freeSpace: 32_000_000_000,
            description: "Internal Storage"
        )
        
        XCTAssertEqual(storageInfo.storageId, 1)
        XCTAssertEqual(storageInfo.maxCapacity, 64_000_000_000)
        XCTAssertEqual(storageInfo.freeSpace, 32_000_000_000)
        XCTAssertEqual(storageInfo.description, "Internal Storage")
        XCTAssertNotNil(storageInfo.id)
    }
    
    func testStorageInfoUsedSpaceCalculation() {
        let storageInfo = StorageInfo(
            storageId: 1,
            maxCapacity: 100_000_000_000,
            freeSpace: 60_000_000_000,
            description: "Test Storage"
        )
        
        XCTAssertEqual(storageInfo.usedSpace, 40_000_000_000)
    }
    
    func testStorageInfoUsagePercentageCalculation() {
        // Test normal case
        let storageInfo1 = StorageInfo(
            storageId: 1,
            maxCapacity: 100_000_000_000,
            freeSpace: 50_000_000_000,
            description: "Test Storage"
        )
        XCTAssertEqual(storageInfo1.usagePercentage, 50.0, accuracy: 0.01)
        
        // Test full storage
        let storageInfo2 = StorageInfo(
            storageId: 2,
            maxCapacity: 100_000_000_000,
            freeSpace: 0,
            description: "Full Storage"
        )
        XCTAssertEqual(storageInfo2.usagePercentage, 100.0, accuracy: 0.01)
        
        // Test empty storage
        let storageInfo3 = StorageInfo(
            storageId: 3,
            maxCapacity: 100_000_000_000,
            freeSpace: 100_000_000_000,
            description: "Empty Storage"
        )
        XCTAssertEqual(storageInfo3.usagePercentage, 0.0, accuracy: 0.01)
        
        // Test zero capacity (edge case)
        let storageInfo4 = StorageInfo(
            storageId: 4,
            maxCapacity: 0,
            freeSpace: 0,
            description: "Zero Capacity"
        )
        XCTAssertEqual(storageInfo4.usagePercentage, 0.0, accuracy: 0.01)
    }
    
    func testStorageInfoBoundaryConditions() {
        // Test very large values
        let largeStorage = StorageInfo(
            storageId: 1,
            maxCapacity: UInt64.max,
            freeSpace: UInt64.max / 2,
            description: "Large Storage"
        )
        XCTAssertEqual(largeStorage.usagePercentage, 50.0, accuracy: 0.01)
        
        // Test very small values
        let tinyStorage = StorageInfo(
            storageId: 2,
            maxCapacity: 1,
            freeSpace: 0,
            description: "Tiny Storage"
        )
        XCTAssertEqual(tinyStorage.usagePercentage, 100.0, accuracy: 0.01)
    }
    
    // MARK: - MTPSupportInfo Tests
    
    func testMTPSupportInfoInitialization() {
        let mtpInfo = MTPSupportInfo(
            mtpVersion: "1.1",
            deviceVersion: "1.0",
            vendorExtension: "android"
        )
        
        XCTAssertEqual(mtpInfo.mtpVersion, "1.1")
        XCTAssertEqual(mtpInfo.deviceVersion, "1.0")
        XCTAssertEqual(mtpInfo.vendorExtension, "android")
        XCTAssertNotNil(mtpInfo.id)
    }
    
    func testMTPSupportInfoEmptyFields() {
        let mtpInfo = MTPSupportInfo(
            mtpVersion: "",
            deviceVersion: "",
            vendorExtension: ""
        )
        
        XCTAssertEqual(mtpInfo.mtpVersion, "")
        XCTAssertEqual(mtpInfo.deviceVersion, "")
        XCTAssertEqual(mtpInfo.vendorExtension, "")
    }
    
    // MARK: - Device Tests
    
    func testDeviceInitialization() {
        let device = Device(
            deviceIndex: 0,
            name: "Test Device",
            manufacturer: "Test Mfg",
            model: "Test Model",
            serialNumber: "TEST123",
            batteryLevel: 80,
            storageInfo: [],
            mtpSupportInfo: nil,
            isConnected: true
        )
        
        XCTAssertEqual(device.deviceIndex, 0)
        XCTAssertEqual(device.name, "Test Device")
        XCTAssertEqual(device.manufacturer, "Test Mfg")
        XCTAssertEqual(device.model, "Test Model")
        XCTAssertEqual(device.serialNumber, "TEST123")
        XCTAssertEqual(device.batteryLevel, 80)
        XCTAssertTrue(device.storageInfo.isEmpty)
        XCTAssertNil(device.mtpSupportInfo)
        XCTAssertTrue(device.isConnected)
        XCTAssertNotNil(device.id)
    }
    
    func testDeviceWithStorageInfo() {
        let storageInfo = StorageInfo(
            storageId: 1,
            maxCapacity: 64_000_000_000,
            freeSpace: 32_000_000_000,
            description: "Internal Storage"
        )
        
        let device = Device(
            deviceIndex: 0,
            name: "Test Device",
            manufacturer: "Test Mfg",
            model: "Test Model",
            serialNumber: "TEST123",
            batteryLevel: nil,
            storageInfo: [storageInfo],
            mtpSupportInfo: nil
        )
        
        XCTAssertEqual(device.storageInfo.count, 1)
        XCTAssertEqual(device.storageInfo[0].storageId, 1)
    }
    
    func testDeviceWithMTPSupportInfo() {
        let mtpInfo = MTPSupportInfo(
            mtpVersion: "1.1",
            deviceVersion: "1.0",
            vendorExtension: "android"
        )
        
        let device = Device(
            deviceIndex: 0,
            name: "Test Device",
            manufacturer: "Test Mfg",
            model: "Test Model",
            serialNumber: "TEST123",
            batteryLevel: nil,
            storageInfo: [],
            mtpSupportInfo: mtpInfo
        )
        
        XCTAssertNotNil(device.mtpSupportInfo)
        XCTAssertEqual(device.mtpSupportInfo?.mtpVersion, "1.1")
    }
    
    func testDeviceDisplayName() {
        // Test with valid name
        let device1 = Device(
            deviceIndex: 0,
            name: "My Phone",
            manufacturer: "Samsung",
            model: "Galaxy S21",
            serialNumber: "TEST123",
            batteryLevel: nil
        )
        XCTAssertEqual(device1.displayName, "My Phone")
        
        // Test with unknown device name
        let device2 = Device(
            deviceIndex: 1,
            name: "Unknown Device",
            manufacturer: "Apple",
            model: "iPhone 13",
            serialNumber: "TEST456",
            batteryLevel: nil
        )
        XCTAssertEqual(device2.displayName, "Apple iPhone 13")
        
        // Test with empty name
        let device3 = Device(
            deviceIndex: 2,
            name: "",
            manufacturer: "Google",
            model: "Pixel 6",
            serialNumber: "TEST789",
            batteryLevel: nil
        )
        XCTAssertEqual(device3.displayName, "Google Pixel 6")
    }
    
    func testDeviceDisplayModel() {
        // Test with name containing manufacturer
        let device1 = Device(
            deviceIndex: 0,
            name: "Samsung Galaxy S21",
            manufacturer: "Samsung",
            model: "Galaxy S21",
            serialNumber: "TEST123",
            batteryLevel: nil
        )
        XCTAssertEqual(device1.displayModel, "Galaxy S21")
        
        // Test with name not containing manufacturer
        let device2 = Device(
            deviceIndex: 1,
            name: "My Phone",
            manufacturer: "Samsung",
            model: "Galaxy S21",
            serialNumber: "TEST456",
            batteryLevel: nil
        )
        XCTAssertEqual(device2.displayModel, "Samsung Galaxy S21")
        
        // Test with unknown device name
        let device3 = Device(
            deviceIndex: 2,
            name: "Unknown Device",
            manufacturer: "Apple",
            model: "iPhone 13",
            serialNumber: "TEST789",
            batteryLevel: nil
        )
        XCTAssertEqual(device3.displayModel, "Apple")
    }
    
    func testDeviceTotalCapacity() {
        let storage1 = StorageInfo(
            storageId: 1,
            maxCapacity: 64_000_000_000,
            freeSpace: 32_000_000_000,
            description: "Internal"
        )
        let storage2 = StorageInfo(
            storageId: 2,
            maxCapacity: 128_000_000_000,
            freeSpace: 64_000_000_000,
            description: "SD Card"
        )
        
        let device = Device(
            deviceIndex: 0,
            name: "Test Device",
            manufacturer: "Test",
            model: "Model",
            serialNumber: "TEST",
            batteryLevel: nil,
            storageInfo: [storage1, storage2]
        )
        
        XCTAssertEqual(device.totalCapacity, 192_000_000_000)
    }
    
    func testDeviceTotalFreeSpace() {
        let storage1 = StorageInfo(
            storageId: 1,
            maxCapacity: 64_000_000_000,
            freeSpace: 32_000_000_000,
            description: "Internal"
        )
        let storage2 = StorageInfo(
            storageId: 2,
            maxCapacity: 128_000_000_000,
            freeSpace: 64_000_000_000,
            description: "SD Card"
        )
        
        let device = Device(
            deviceIndex: 0,
            name: "Test Device",
            manufacturer: "Test",
            model: "Model",
            serialNumber: "TEST",
            batteryLevel: nil,
            storageInfo: [storage1, storage2]
        )
        
        XCTAssertEqual(device.totalFreeSpace, 96_000_000_000)
    }
    
    func testDeviceWithNoStorage() {
        let device = Device(
            deviceIndex: 0,
            name: "Test Device",
            manufacturer: "Test",
            model: "Model",
            serialNumber: "TEST",
            batteryLevel: nil,
            storageInfo: []
        )
        
        XCTAssertEqual(device.totalCapacity, 0)
        XCTAssertEqual(device.totalFreeSpace, 0)
    }
    
    // MARK: - Hashable and Equatable Tests
    
    func testDeviceHashable() {
        let device1 = Device(
            deviceIndex: 0,
            name: "Test Device",
            manufacturer: "Test",
            model: "Model",
            serialNumber: "TEST1",
            batteryLevel: nil
        )
        let device2 = Device(
            deviceIndex: 1,
            name: "Test Device",
            manufacturer: "Test",
            model: "Model",
            serialNumber: "TEST2",
            batteryLevel: nil
        )
        
        // Different devices should have different hashes
        XCTAssertNotEqual(device1.hashValue, device2.hashValue)
    }
    
    func testDeviceEquality() {
        let device1 = Device(
            deviceIndex: 0,
            name: "Test Device",
            manufacturer: "Test",
            model: "Model",
            serialNumber: "TEST1",
            batteryLevel: nil
        )
        let device2 = Device(
            deviceIndex: 1,
            name: "Test Device",
            manufacturer: "Test",
            model: "Model",
            serialNumber: "TEST2",
            batteryLevel: nil
        )
        
        // Different devices should not be equal
        XCTAssertNotEqual(device1, device2)
        
        // Same device should be equal to itself
        XCTAssertEqual(device1, device1)
    }
    
        func testDeviceInSet() {
            let deviceId = UUID()
            let device1 = Device(
                id: deviceId,
                deviceIndex: 0,
                name: "Test Device",
                manufacturer: "Test",
                model: "Model",
                serialNumber: "TEST1",
                batteryLevel: nil
            )
            let device2 = Device(
                id: deviceId,
                deviceIndex: 0,
                name: "Test Device",
                manufacturer: "Test",
                model: "Model",
                serialNumber: "TEST1",
                batteryLevel: nil
            )
        
        var deviceSet: Set<Device> = []
        deviceSet.insert(device1)
        deviceSet.insert(device2)
        
        // Should only contain one device (same id)
        XCTAssertEqual(deviceSet.count, 1)
    }
    
    // MARK: - Boundary and Edge Cases
    
    func testDeviceBatteryLevelBoundary() {
        // Test nil battery level
        let device1 = Device(
            deviceIndex: 0,
            name: "Test",
            manufacturer: "Test",
            model: "Model",
            serialNumber: "TEST",
            batteryLevel: nil
        )
        XCTAssertNil(device1.batteryLevel)
        
        // Test 0% battery
        let device2 = Device(
            deviceIndex: 1,
            name: "Test",
            manufacturer: "Test",
            model: "Model",
            serialNumber: "TEST",
            batteryLevel: 0
        )
        XCTAssertEqual(device2.batteryLevel, 0)
        
        // Test 100% battery
        let device3 = Device(
            deviceIndex: 2,
            name: "Test",
            manufacturer: "Test",
            model: "Model",
            serialNumber: "TEST",
            batteryLevel: 100
        )
        XCTAssertEqual(device3.batteryLevel, 100)
    }
    
    func testDeviceEmptyStrings() {
        let device = Device(
            deviceIndex: 0,
            name: "",
            manufacturer: "",
            model: "",
            serialNumber: "",
            batteryLevel: nil
        )
        
        XCTAssertEqual(device.name, "")
        XCTAssertEqual(device.manufacturer, "")
        XCTAssertEqual(device.model, "")
        XCTAssertEqual(device.serialNumber, "")
        XCTAssertEqual(device.displayName, " ")
    }
    
    func testMultipleStorageDevices() {
        var storages: [StorageInfo] = []
        for index in 0..<10 {
            let storage = StorageInfo(
                storageId: UInt32(index),
                maxCapacity: UInt64(index + 1) * 10_000_000_000,
                freeSpace: UInt64(index + 1) * 5_000_000_000,
                description: "Storage \(index)"
            )
            storages.append(storage)
        }
        
        let device = Device(
            deviceIndex: 0,
            name: "Multi-Storage Device",
            manufacturer: "Test",
            model: "Model",
            serialNumber: "TEST",
            batteryLevel: nil,
            storageInfo: storages
        )
        
        XCTAssertEqual(device.storageInfo.count, 10)
        XCTAssertEqual(device.totalCapacity, 550_000_000_000) // Sum of 10+20+...+100 = 550 GB
        XCTAssertEqual(device.totalFreeSpace, 275_000_000_000) // Half of total
    }
}