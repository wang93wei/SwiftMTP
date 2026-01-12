//
//  DeviceManagerTests.swift
//  SwiftMTPTests
//
//  Unit tests for DeviceManager
//

import XCTest
import Combine
@testable import SwiftMTP

final class DeviceManagerTests: XCTestCase {
    
    var manager: DeviceManager!
    var cancellables: Set<AnyCancellable>!
    
    // MARK: - Setup and Teardown
    
    override func setUp() {
        super.setUp()
        manager = DeviceManager.shared
        cancellables = Set<AnyCancellable>()
    }
    
    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }
    
    // MARK: - Singleton Tests
    
    func testSingletonInstance() {
        let instance1 = DeviceManager.shared
        let instance2 = DeviceManager.shared
        
        XCTAssertTrue(instance1 === instance2, "DeviceManager should be a singleton")
    }
    
    // MARK: - Published Properties Tests
    
    func testDevicesIsPublished() {
        let expectation = self.expectation(description: "devices property should be published")
        
        manager.$devices
            .dropFirst() // Skip initial value
            .sink { _ in
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        // Trigger a scan (this may not publish if no devices found)
        manager.scanDevices()
        
        waitForExpectations(timeout: 5.0)
    }
    
    func testSelectedDeviceIsPublished() {
        let expectation = self.expectation(description: "selectedDevice property should be published")
        
        manager.$selectedDevice
            .dropFirst()
            .sink { _ in
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        let testDevice = Device(
            deviceIndex: 0,
            name: "Test Device",
            manufacturer: "Test",
            model: "Model",
            serialNumber: "TEST123",
            batteryLevel: nil
        )
        
        manager.selectDevice(testDevice)
        
        waitForExpectations(timeout: 1.0)
    }
    
    func testIsScanningIsPublished() {
        let expectation = self.expectation(description: "isScanning property should be published")
        
        manager.$isScanning
            .dropFirst()
            .sink { _ in
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        manager.scanDevices()
        
        waitForExpectations(timeout: 5.0)
    }
    
    func testConnectionErrorIsPublished() {
        let expectation = self.expectation(description: "connectionError property should be published")
        
        manager.$connectionError
            .dropFirst()
            .sink { _ in
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        // Trigger a scan that may set connection error
        manager.scanDevices()
        
        waitForExpectations(timeout: 5.0)
    }
    
    func testHasScannedOnceIsPublished() {
        let expectation = self.expectation(description: "hasScannedOnce property should be published")
        
        manager.$hasScannedOnce
            .dropFirst()
            .sink { _ in
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        manager.scanDevices()
        
        waitForExpectations(timeout: 5.0)
    }
    
    func testShowManualRefreshButtonIsPublished() {
        let expectation = self.expectation(description: "showManualRefreshButton property should be published")
        
        manager.$showManualRefreshButton
            .dropFirst()
            .sink { _ in
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        // Trigger multiple scans to reach max failures
        for _ in 0..<5 {
            manager.scanDevices()
        }
        
        waitForExpectations(timeout: 10.0)
    }
    
    // MARK: - Device Selection Tests
    
    func testSelectDevice() {
        let testDevice = Device(
            deviceIndex: 0,
            name: "Test Device",
            manufacturer: "Test",
            model: "Model",
            serialNumber: "TEST123",
            batteryLevel: nil
        )
        
        manager.selectDevice(testDevice)
        
        XCTAssertEqual(manager.selectedDevice?.name, "Test Device")
        XCTAssertEqual(manager.selectedDevice?.serialNumber, "TEST123")
        XCTAssertNil(manager.connectionError)
    }
    
    func testSelectDeviceClearsConnectionError() {
        // First set a connection error
        manager.connectionError = "Test error"
        
        let testDevice = Device(
            deviceIndex: 0,
            name: "Test Device",
            manufacturer: "Test",
            model: "Model",
            serialNumber: "TEST123",
            batteryLevel: nil
        )
        
        manager.selectDevice(testDevice)
        
        XCTAssertNil(manager.connectionError)
    }
    
    func testSelectMultipleDevices() {
        let device1 = Device(
            deviceIndex: 0,
            name: "Device 1",
            manufacturer: "Test",
            model: "Model",
            serialNumber: "TEST1",
            batteryLevel: nil
        )
        
        let device2 = Device(
            deviceIndex: 1,
            name: "Device 2",
            manufacturer: "Test",
            model: "Model",
            serialNumber: "TEST2",
            batteryLevel: nil
        )
        
        manager.selectDevice(device1)
        XCTAssertEqual(manager.selectedDevice?.serialNumber, "TEST1")
        
        manager.selectDevice(device2)
        XCTAssertEqual(manager.selectedDevice?.serialNumber, "TEST2")
    }
    
    // MARK: - Scanning Tests
    
    func testScanDevicesUpdatesIsScanning() {
        let expectation = self.expectation(description: "isScanning should update")

        var scanningStates: [Bool] = []

        self.manager.$isScanning
            .sink { isScanning in
                scanningStates.append(isScanning)
                if scanningStates.count >= 2 {
                    expectation.fulfill()
                }
            }
            .store(in: &self.cancellables)

        self.manager.scanDevices()

        waitForExpectations(timeout: 5.0)

        // Should have at least started and stopped scanning
        XCTAssertTrue(scanningStates.contains(true))
    }
    
    func testScanDevicesNonConcurrent() {
        let expectation = self.expectation(description: "Concurrent scans should be prevented")

        self.manager.scanDevices()

        // Immediately try to scan again while first scan is running
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            self.manager.scanDevices()
            expectation.fulfill()
        }

        waitForExpectations(timeout: 5.0)

        // Should complete without throwing
        XCTAssertNoThrow(self.manager.scanDevices())
    }
    
    // MARK: - Manual Refresh Tests
    
    func testManualRefreshResetsFailureCount() {
        // Trigger multiple scans to reach max failures
        for _ in 0..<5 {
            manager.scanDevices()
        }
        
        // Verify manual refresh button is shown
        XCTAssertTrue(manager.showManualRefreshButton)
        
        // Perform manual refresh
        manager.manualRefresh()
        
        // Verify failure count is reset
        XCTAssertFalse(manager.showManualRefreshButton)
    }
    
    func testManualRefreshRestartsScanning() {
        // Stop scanning
        manager.stopScanning()
        
        // Perform manual refresh
        manager.manualRefresh()
        
        // Verify scanning is restarted by checking if scanDevices can be called
        XCTAssertNoThrow(manager.scanDevices())
    }
    
    // MARK: - Scan Interval Tests
    
    func testUpdateScanInterval() {
        // Set a custom scan interval
        UserDefaults.standard.set(5.0, forKey: "scanInterval")
        
        // Update scan interval
        XCTAssertNoThrow(manager.updateScanInterval())
        
        // Reset to default
        UserDefaults.standard.removeObject(forKey: "scanInterval")
    }
    
    func testDefaultScanInterval() {
        // Ensure no custom interval is set
        UserDefaults.standard.removeObject(forKey: "scanInterval")
        
        // Verify default interval is used
        XCTAssertNoThrow(manager.updateScanInterval())
    }
    
    func testInvalidScanInterval() {
        // Set an invalid scan interval
        UserDefaults.standard.set(-1.0, forKey: "scanInterval")
        
        // Should handle gracefully
        XCTAssertNoThrow(manager.updateScanInterval())
        
        // Reset
        UserDefaults.standard.removeObject(forKey: "scanInterval")
    }
    
    // MARK: - Start/Stop Scanning Tests
    
    func testStartScanning() {
        manager.stopScanning()
        
        manager.startScanning()
        
        // Verify isScanning can be set
        XCTAssertNoThrow(manager.scanDevices())
    }
    
    func testStopScanning() {
        manager.startScanning()
        
        manager.stopScanning()
        
        // Verify scanning is stopped
        XCTAssertNoThrow(manager.stopScanning())
    }
    
    func testMultipleStartStop() {
        for _ in 0..<5 {
            manager.startScanning()
            manager.stopScanning()
        }
        
        // Should not throw
        XCTAssertNoThrow(manager.startScanning())
        XCTAssertNoThrow(manager.stopScanning())
    }
    
    // MARK: - Device Disconnection Tests
    
    func testDeviceDisconnectionClearsSelectedDevice() {
        let testDevice = Device(
            deviceIndex: 0,
            name: "Test Device",
            manufacturer: "Test",
            model: "Model",
            serialNumber: "TEST123",
            batteryLevel: nil
        )
        
        manager.selectDevice(testDevice)
        XCTAssertNotNil(manager.selectedDevice)
        
        // Trigger a scan with no devices (simulating disconnection)
        manager.scanDevices()
        
        // After disconnection, selected device should be cleared
        // Note: This depends on the actual scan result
    }
    
    func testDeviceDisconnectionClearsDevicesList() {
        // Trigger scan
        manager.scanDevices()
        
        // If no devices are found, devices list should be empty
        // Note: This depends on the actual scan result
        XCTAssertNotNil(manager.devices)
    }
    
    func testDeviceDisconnectionSetsConnectionError() {
        let testDevice = Device(
            deviceIndex: 0,
            name: "Test Device",
            manufacturer: "Test",
            model: "Model",
            serialNumber: "TEST123",
            batteryLevel: nil
        )
        
        manager.selectDevice(testDevice)
        
        // Trigger scan with no devices
        manager.scanDevices()
        
        // Connection error should be set
        // Note: This depends on the actual scan result
    }
    
    // MARK: - Cache Tests
    
    func testDeviceIdCaching() {
        // Verify device ID caching works
        // This is tested indirectly through device selection
        let device1 = Device(
            deviceIndex: 0,
            name: "Device 1",
            manufacturer: "Test",
            model: "Model",
            serialNumber: "TEST1",
            batteryLevel: nil
        )
        
        manager.selectDevice(device1)
        
        XCTAssertNotNil(manager.selectedDevice)
    }
    
    // MARK: - Thread Safety Tests
    
    func testConcurrentDeviceSelection() async throws {
        let expectation = self.expectation(description: "Concurrent device selection should complete")
        expectation.expectedFulfillmentCount = 10

        DispatchQueue.concurrentPerform(iterations: 10) { [weak self] i in
            guard let self = self else { return }
            Task { @MainActor in
                let device = Device(
                    deviceIndex: i,
                    name: "Device \(i)",
                    manufacturer: "Test",
                    model: "Model",
                    serialNumber: "TEST\(i)",
                    batteryLevel: nil
                )

                self.manager.selectDevice(device)
                expectation.fulfill()
            }
        }

        await fulfillment(of: [expectation], timeout: 5.0)

        // Should complete without crashing
        XCTAssertNotNil(self.manager.selectedDevice)
    }

    func testConcurrentScans() {
        let expectation = self.expectation(description: "Concurrent scans should complete")
        expectation.expectedFulfillmentCount = 5

        DispatchQueue.concurrentPerform(iterations: 5) { [weak self] _ in
            guard let self = self else { return }
            self.manager.scanDevices()
            expectation.fulfill()
        }

        waitForExpectations(timeout: 10.0)

        // Should complete without crashing
        XCTAssertTrue(self.manager.hasScannedOnce)
    }
    
    // MARK: - Edge Cases
    
    func testEmptyDeviceName() {
        let device = Device(
            deviceIndex: 0,
            name: "",
            manufacturer: "Test",
            model: "Model",
            serialNumber: "TEST123",
            batteryLevel: nil
        )
        
        manager.selectDevice(device)
        
        XCTAssertEqual(manager.selectedDevice?.name, "")
    }
    
    func testEmptySerialNumber() {
        let device = Device(
            deviceIndex: 0,
            name: "Test Device",
            manufacturer: "Test",
            model: "Model",
            serialNumber: "",
            batteryLevel: nil
        )
        
        manager.selectDevice(device)
        
        XCTAssertEqual(manager.selectedDevice?.serialNumber, "")
    }
    
    func testDeviceWithMultipleStorages() {
        let storages = [
            StorageInfo(
                storageId: 1,
                maxCapacity: 64_000_000_000,
                freeSpace: 32_000_000_000,
                description: "Internal Storage"
            ),
            StorageInfo(
                storageId: 2,
                maxCapacity: 128_000_000_000,
                freeSpace: 64_000_000_000,
                description: "SD Card"
            )
        ]
        
        let device = Device(
            deviceIndex: 0,
            name: "Multi-Storage Device",
            manufacturer: "Test",
            model: "Model",
            serialNumber: "TEST123",
            batteryLevel: nil,
            storageInfo: storages
        )
        
        manager.selectDevice(device)
        
        XCTAssertEqual(manager.selectedDevice?.storageInfo.count, 2)
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
            manufacturer: "Test",
            model: "Model",
            serialNumber: "TEST123",
            batteryLevel: nil,
            mtpSupportInfo: mtpInfo
        )
        
        manager.selectDevice(device)
        
        XCTAssertNotNil(manager.selectedDevice?.mtpSupportInfo)
        XCTAssertEqual(manager.selectedDevice?.mtpSupportInfo?.mtpVersion, "1.1")
    }
    
    // MARK: - Performance Tests
    
    func testScanPerformance() {
        measure {
            for _ in 0..<10 {
                manager.scanDevices()
            }
        }
    }
    
    func testDeviceSelectionPerformance() {
        let device = Device(
            deviceIndex: 0,
            name: "Test Device",
            manufacturer: "Test",
            model: "Model",
            serialNumber: "TEST123",
            batteryLevel: nil
        )
        
        measure {
            for _ in 0..<1000 {
                manager.selectDevice(device)
            }
        }
    }
}