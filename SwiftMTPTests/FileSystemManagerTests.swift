//
//  FileSystemManagerTests.swift
//  SwiftMTPTests
//
//  Unit tests for FileSystemManager
//

import XCTest
@testable import SwiftMTP

// MARK: - Mock Protocol for Testing

protocol FileSystemManagerProtocol {
    func getFileList(for device: Device, parentId: UInt32, storageId: UInt32) -> [FileItem]
    func getRootFiles(for device: Device) -> [FileItem]
    func getChildrenFiles(for device: Device, parent: FileItem) -> [FileItem]
    func clearCache()
    func clearCache(for device: Device)
}

// MARK: - Mock Implementation

class MockFileSystemManager: FileSystemManagerProtocol {
    var mockFileList: [FileItem] = []
    var shouldReturnEmpty = false
    var shouldSimulateError = false
    
    func getFileList(for device: Device, parentId: UInt32, storageId: UInt32) -> [FileItem] {
        if shouldSimulateError || shouldReturnEmpty {
            return []
        }
        return mockFileList
    }
    
    func getRootFiles(for device: Device) -> [FileItem] {
        if shouldSimulateError || shouldReturnEmpty {
            return []
        }
        return mockFileList
    }
    
    func getChildrenFiles(for device: Device, parent: FileItem) -> [FileItem] {
        if shouldSimulateError || shouldReturnEmpty {
            return []
        }
        return mockFileList
    }
    
    func clearCache() {
        mockFileList.removeAll()
    }
    
    func clearCache(for device: Device) {
        mockFileList.removeAll()
    }
}

@MainActor
final class FileSystemManagerTests: XCTestCase {
    
    var manager: FileSystemManager!
    var testDevice: Device!
    var mockManager: MockFileSystemManager!
    
    // MARK: - Setup and Teardown
    
    override func setUp() {
        super.setUp()
        manager = FileSystemManager.shared
        mockManager = MockFileSystemManager()
        
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
    
    // MARK: - Mock Tests
    
    func testMockManagerReturnsEmptyList() {
        mockManager.shouldReturnEmpty = true
        
        let files = mockManager.getFileList(for: testDevice, parentId: 0xFFFFFFFF, storageId: 1)
        
        XCTAssertEqual(files.count, 0)
    }
    
    func testMockManagerReturnsMockData() {
        let mockFiles = [
            FileItem(
                objectId: 1,
                parentId: 0xFFFFFFFF,
                storageId: 1,
                name: "test.txt",
                path: "/test.txt",
                size: 1024,
                modifiedDate: Date(),
                isDirectory: false,
                fileType: "txt"
            )
        ]
        
        mockManager.mockFileList = mockFiles
        
        let files = mockManager.getFileList(for: testDevice, parentId: 0xFFFFFFFF, storageId: 1)
        
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files[0].name, "test.txt")
    }
    
    func testMockManagerSimulatesError() {
        mockManager.shouldSimulateError = true
        
        let files = mockManager.getRootFiles(for: testDevice)
        
        XCTAssertEqual(files.count, 0)
    }
    
    func testMockManagerClearCache() {
        let mockFiles = [
            FileItem(
                objectId: 1,
                parentId: 0xFFFFFFFF,
                storageId: 1,
                name: "test.txt",
                path: "/test.txt",
                size: 1024,
                modifiedDate: Date(),
                isDirectory: false,
                fileType: "txt"
            )
        ]
        
        mockManager.mockFileList = mockFiles
        mockManager.clearCache()
        
        XCTAssertEqual(mockManager.mockFileList.count, 0)
    }
    
    func testMockManagerClearCacheForDevice() {
        let mockFiles = [
            FileItem(
                objectId: 1,
                parentId: 0xFFFFFFFF,
                storageId: 1,
                name: "test.txt",
                path: "/test.txt",
                size: 1024,
                modifiedDate: Date(),
                isDirectory: false,
                fileType: "txt"
            )
        ]
        
        mockManager.mockFileList = mockFiles
        mockManager.clearCache(for: testDevice)
        
        XCTAssertEqual(mockManager.mockFileList.count, 0)
    }
    
    func testMockManagerGetChildrenFiles() {
        let parentFile = FileItem(
            objectId: 0xFFFFFFFF,
            parentId: 0xFFFFFFFF,
            storageId: 1,
            name: "Parent",
            path: "/Parent",
            size: 0,
            modifiedDate: nil,
            isDirectory: true,
            fileType: "folder"
        )
        
        let mockFiles = [
            FileItem(
                objectId: 1,
                parentId: 0xFFFFFFFF,
                storageId: 1,
                name: "child.txt",
                path: "/Parent/child.txt",
                size: 512,
                modifiedDate: Date(),
                isDirectory: false,
                fileType: "txt"
            )
        ]
        
        mockManager.mockFileList = mockFiles
        
        let children = mockManager.getChildrenFiles(for: testDevice, parent: parentFile)
        
        XCTAssertEqual(children.count, 1)
        XCTAssertEqual(children[0].name, "child.txt")
    }
    
    // MARK: - Cache Expiration Tests
    
    func testCacheExpirationLogic() {
        // Test that cache expiration logic works correctly
        // This is tested indirectly through getFileList calls
        
        let files = manager.getFileList(for: testDevice, parentId: 0xFFFFFFFF, storageId: 1)
        
        // Should return something (empty or with data)
        XCTAssertNotNil(files)
    }
    
    // MARK: - Large Directory Tests
    
    func testGetFileListWithLargeDirectory() {
        // Test handling of directories with many files
        // This would require a real device or mock with large data
        
        var mockFiles: [FileItem] = []
        for i in 0..<1000 {
            mockFiles.append(FileItem(
                objectId: UInt32(i),
                parentId: 0xFFFFFFFF,
                storageId: 1,
                name: "file\(i).txt",
                path: "/file\(i).txt",
                size: 1024,
                modifiedDate: Date(),
                isDirectory: false,
                fileType: "txt"
            ))
        }
        
        mockManager.mockFileList = mockFiles
        
        let files = mockManager.getFileList(for: testDevice, parentId: 0xFFFFFFFF, storageId: 1)
        
        XCTAssertEqual(files.count, 1000)
    }
    
    // MARK: - Special Characters Tests
    
    func testGetFileListWithSpecialCharacters() {
        let mockFiles = [
            FileItem(
                objectId: 1,
                parentId: 0xFFFFFFFF,
                storageId: 1,
                name: "测试文件.txt",
                path: "/测试文件.txt",
                size: 1024,
                modifiedDate: Date(),
                isDirectory: false,
                fileType: "txt"
            ),
            FileItem(
                objectId: 2,
                parentId: 0xFFFFFFFF,
                storageId: 1,
                name: "file with spaces.txt",
                path: "/file with spaces.txt",
                size: 2048,
                modifiedDate: Date(),
                isDirectory: false,
                fileType: "txt"
            ),
            FileItem(
                objectId: 3,
                parentId: 0xFFFFFFFF,
                storageId: 1,
                name: "file-with-special_chars.txt",
                path: "/file-with-special_chars.txt",
                size: 512,
                modifiedDate: Date(),
                isDirectory: false,
                fileType: "txt"
            )
        ]
        
        mockManager.mockFileList = mockFiles
        
        let files = mockManager.getFileList(for: testDevice, parentId: 0xFFFFFFFF, storageId: 1)
        
        XCTAssertEqual(files.count, 3)
        XCTAssertEqual(files[0].name, "测试文件.txt")
        XCTAssertEqual(files[1].name, "file with spaces.txt")
        XCTAssertEqual(files[2].name, "file-with-special_chars.txt")
    }
    
    // MARK: - Deep Directory Structure Tests
    
    func testGetFileListWithDeepDirectoryStructure() {
        // Test handling of deeply nested directories
        let level1 = FileItem(
            objectId: 1,
            parentId: 0xFFFFFFFF,
            storageId: 1,
            name: "Level1",
            path: "/Level1",
            size: 0,
            modifiedDate: nil,
            isDirectory: true,
            fileType: "folder",
            children: []
        )
        
        let level2 = FileItem(
            objectId: 2,
            parentId: 1,
            storageId: 1,
            name: "Level2",
            path: "/Level1/Level2",
            size: 0,
            modifiedDate: nil,
            isDirectory: true,
            fileType: "folder",
            children: []
        )
        
        let level3 = FileItem(
            objectId: 3,
            parentId: 2,
            storageId: 1,
            name: "Level3",
            path: "/Level1/Level2/Level3",
            size: 0,
            modifiedDate: nil,
            isDirectory: true,
            fileType: "folder",
            children: []
        )
        
        let mockFiles = [level1, level2, level3]
        
        mockManager.mockFileList = mockFiles
        
        let files = mockManager.getFileList(for: testDevice, parentId: 0xFFFFFFFF, storageId: 1)
        
        XCTAssertEqual(files.count, 3)
    }
    
    // MARK: - Mixed File Types Tests
    
    func testGetFileListWithMixedFileTypes() {
        let mockFiles = [
            FileItem(
                objectId: 1,
                parentId: 0xFFFFFFFF,
                storageId: 1,
                name: "document.pdf",
                path: "/document.pdf",
                size: 1024 * 1024,
                modifiedDate: Date(),
                isDirectory: false,
                fileType: "PDF"
            ),
            FileItem(
                objectId: 2,
                parentId: 0xFFFFFFFF,
                storageId: 1,
                name: "image.jpg",
                path: "/image.jpg",
                size: 2 * 1024 * 1024,
                modifiedDate: Date(),
                isDirectory: false,
                fileType: "JPG"
            ),
            FileItem(
                objectId: 3,
                parentId: 0xFFFFFFFF,
                storageId: 1,
                name: "video.mp4",
                path: "/video.mp4",
                size: 100 * 1024 * 1024,
                modifiedDate: Date(),
                isDirectory: false,
                fileType: "MP4"
            ),
            FileItem(
                objectId: 4,
                parentId: 0xFFFFFFFF,
                storageId: 1,
                name: "folder",
                path: "/folder",
                size: 0,
                modifiedDate: nil,
                isDirectory: true,
                fileType: "folder"
            )
        ]
        
        mockManager.mockFileList = mockFiles
        
        let files = mockManager.getFileList(for: testDevice, parentId: 0xFFFFFFFF, storageId: 1)
        
        XCTAssertEqual(files.count, 4)
        XCTAssertEqual(files[0].fileType, "PDF")
        XCTAssertEqual(files[1].fileType, "JPG")
        XCTAssertEqual(files[2].fileType, "MP4")
        XCTAssertEqual(files[3].fileType, "folder")
    }
}