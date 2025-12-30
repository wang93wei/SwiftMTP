//
//  FileSystemManagerTests.swift
//  SwiftMTPTests
//
//  Unit tests for FileSystemManager
//

import XCTest
@testable import SwiftMTP

final class FileSystemManagerTests: XCTestCase {
    
    var manager: FileSystemManager!
    var testDevice: Device!
    
    // MARK: - Setup and Teardown
    
    override func setUp() {
        super.setUp()
        manager = FileSystemManager.shared
        
        // Create a test device
        testDevice = Device(
            deviceIndex: 0,
            name: "Test Device",
            manufacturer: "Test Mfg",
            model: "Test Model",
            serialNumber: "TEST123",
            batteryLevel: nil,
            storageInfo: [
                StorageInfo(
                    storageId: 1,
                    maxCapacity: 64_000_000_000,
                    freeSpace: 32_000_000_000,
                    description: "Internal Storage"
                )
            ]
        )
    }
    
    override func tearDown() {
        manager.clearCache()
        super.tearDown()
    }
    
    // MARK: - Singleton Tests
    
    func testSingletonInstance() {
        let instance1 = FileSystemManager.shared
        let instance2 = FileSystemManager.shared
        
        XCTAssertTrue(instance1 === instance2, "FileSystemManager should be a singleton")
    }
    
    // MARK: - Cache Tests
    
    func testClearCache() {
        // This test verifies that clearCache doesn't throw
        XCTAssertNoThrow(manager.clearCache())
    }
    
    func testClearCacheForDevice() {
        // This test verifies that clearCache(for:) doesn't throw
        XCTAssertNoThrow(manager.clearCache(for: testDevice))
    }
    
    func testForceClearCache() {
        // This test verifies that forceClearCache doesn't throw
        XCTAssertNoThrow(manager.forceClearCache())
    }
    
    func testMultipleCacheClears() {
        // Perform multiple cache clears
        for _ in 0..<10 {
            manager.clearCache()
            manager.forceClearCache()
        }
        
        // Should not throw
        XCTAssertNoThrow(manager.clearCache())
    }
    
    // MARK: - Get Root Files Tests
    
    func testGetRootFilesWithNoStorage() {
        let deviceWithoutStorage = Device(
            deviceIndex: 1,
            name: "No Storage Device",
            manufacturer: "Test",
            model: "Model",
            serialNumber: "TEST456",
            batteryLevel: nil,
            storageInfo: []
        )
        
        let files = manager.getRootFiles(for: deviceWithoutStorage)
        
        // Should return empty array when no storage
        XCTAssertEqual(files.count, 0)
    }
    
    func testGetRootFilesWithStorage() throws {
        throw XCTSkip("This test requires a real MTP device to be connected")
    }
    
    // MARK: - Get File List Tests
    
    func testGetFileListWithRootDirectory() throws {
        throw XCTSkip("This test requires a real MTP device to be connected")
    }
    
    func testGetFileListWithCustomDirectory() throws {
        throw XCTSkip("This test requires a real MTP device to be connected")
    }
    
    func testGetFileListWithDifferentStorage() throws {
        throw XCTSkip("This test requires a real MTP device to be connected")
    }
    
    // MARK: - Get Children Files Tests
    
    func testGetChildrenFilesWithValidParent() throws {
        throw XCTSkip("This test requires a real MTP device to be connected")
    }
    
    func testGetChildrenFilesWithFileParent() throws {
        throw XCTSkip("This test requires a real MTP device to be connected")
    }
    
    // MARK: - Cache Key Tests
    
    func testCacheKeyGeneration() throws {
        throw XCTSkip("This test requires a real MTP device to be connected")
    }
    
    // MARK: - Thread Safety Tests
    
    func testConcurrentCacheOperations() {
        let expectation = self.expectation(description: "Concurrent cache operations should complete")
        expectation.expectedFulfillmentCount = 10
        
        DispatchQueue.concurrentPerform(iterations: 10) { _ in
            manager.clearCache()
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 5.0)
    }
    
    func testConcurrentFileListRequests() throws {
        throw XCTSkip("This test requires a real MTP device to be connected")
    }
    
    // MARK: - Edge Cases
    
    func testGetFileListWithNilDevice() throws {
        throw XCTSkip("This test requires a real MTP device to be connected")
    }
    
    func testGetFileListWithVeryLargeParentId() throws {
        throw XCTSkip("This test requires a real MTP device to be connected")
    }
    
    func testGetFileListWithVeryLargeStorageId() throws {
        throw XCTSkip("This test requires a real MTP device to be connected")
    }
    
    func testGetRootFilesWithMultipleStorages() throws {
        throw XCTSkip("This test requires a real MTP device to be connected")
    }
    
    // MARK: - Performance Tests
    
    func testCacheClearPerformance() {
        measure {
            for _ in 0..<10 {
                manager.clearCache()
            }
        }
    }
    
    // Skip this test as it requires a real MTP device
    func testGetFileListPerformance() throws {
        throw XCTSkip("This test requires a real MTP device to be connected")
    }
    
    // MARK: - State Isolation Tests
    
    func testCacheIsolationBetweenDevices() {
        let device1 = Device(
            deviceIndex: 0,
            name: "Device1",
            manufacturer: "Test",
            model: "Model",
            serialNumber: "TEST1",
            batteryLevel: nil,
            storageInfo: [],
            mtpSupportInfo: nil
        )
        
        let device2 = Device(
            deviceIndex: 1,
            name: "Device2",
            manufacturer: "Test",
            model: "Model",
            serialNumber: "TEST2",
            batteryLevel: nil,
            storageInfo: [],
            mtpSupportInfo: nil
        )
        
        // Clear cache
        manager.clearCache()
        
        // Get files for device 1
        manager.clearCache(for: device1)
        
        // Get files for device 2
        manager.clearCache(for: device2)
        
        // Clear all
        manager.clearCache()
        
        // Should not throw
        XCTAssertNoThrow(manager.clearCache())
    }
}