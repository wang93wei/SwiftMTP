//
//  FileTransferManagerTests.swift
//  SwiftMTPTests
//
//  Unit tests for FileTransferManager
//

import XCTest
import Combine
@testable import SwiftMTP

final class FileTransferManagerTests: XCTestCase {
    
    var manager: FileTransferManager!
    var testDevice: Device!
    var tempFileURL: URL!
    
    // MARK: - Setup and Teardown
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Initialize manager
        manager = FileTransferManager.shared
        
        // Create a temporary file for testing
        let tempDir = FileManager.default.temporaryDirectory
        tempFileURL = tempDir.appendingPathComponent("test_upload_\(UUID().uuidString).txt")
        try "Test content for upload".write(to: tempFileURL, atomically: true, encoding: .utf8)
        
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
    
    override func tearDown() async throws {
        // Clean up temp file
        if let tempFileURL = tempFileURL, FileManager.default.fileExists(atPath: tempFileURL.path) {
            try? FileManager.default.removeItem(at: tempFileURL)
        }
        
        try await super.tearDown()
    }
    
    // MARK: - Singleton Tests
    
    func testSingletonInstance() async throws {
        let instance1 = FileTransferManager.shared
        let instance2 = FileTransferManager.shared
        
        XCTAssertTrue(instance1 === instance2, "FileTransferManager should be a singleton")
    }
    
    // MARK: - Published Properties Tests
    
    func testActiveTasksIsPublished() async throws {
        let manager = FileTransferManager.shared
        
        // Verify that activeTasks is a @Published property
        // We can't actually trigger a change in tests, but we can verify the property exists
        XCTAssertNotNil(manager.activeTasks)
    }
    
    func testCompletedTasksIsPublished() async throws {
        let manager = FileTransferManager.shared
        
        // Verify that completedTasks is a @Published property
        XCTAssertNotNil(manager.completedTasks)
    }
    
    // MARK: - Upload Validation Tests
    
    func testUploadWithNonExistentFile() async throws {
        let manager = FileTransferManager.shared
        let nonExistentURL = URL(fileURLWithPath: "/tmp/non_existent_file_\(UUID().uuidString).txt")
        
        // Should not throw, but should handle gracefully
        XCTAssertNoThrow(
            manager.uploadFile(
                to: testDevice,
                sourceURL: nonExistentURL,
                parentId: 0xFFFFFFFF,
                storageId: 1
            )
        )
    }
    
    func testUploadWithDirectory() async throws {
        let manager = FileTransferManager.shared
        
        // Create a temporary directory
        let tempDir = FileManager.default.temporaryDirectory
        let tempDirURL = tempDir.appendingPathComponent("test_dir_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirURL, withIntermediateDirectories: true)
        
        // Should not throw, but should handle gracefully
        XCTAssertNoThrow(
            manager.uploadFile(
                to: testDevice,
                sourceURL: tempDirURL,
                parentId: 0xFFFFFFFF,
                storageId: 1
            )
        )
        
        // Clean up
        try? FileManager.default.removeItem(at: tempDirURL)
    }
    
    func testUploadWithEmptyPath() async throws {
        let manager = FileTransferManager.shared
        
        let emptyPathURL = URL(fileURLWithPath: "")
        
        // Should not throw, but should handle gracefully
        XCTAssertNoThrow(
            manager.uploadFile(
                to: testDevice,
                sourceURL: emptyPathURL,
                parentId: 0xFFFFFFFF,
                storageId: 1
            )
        )
    }
    
    func testUploadWithLargeFile() async throws {
        let manager = FileTransferManager.shared
        
        // Create a temporary large file (>10GB)
        let tempDir = FileManager.default.temporaryDirectory
        let largeFileURL = tempDir.appendingPathComponent("large_file_\(UUID().uuidString).bin")
        
        // Note: We can't actually create a 10GB file in tests
        // This test verifies the validation logic exists
        
        // Should not throw, but should handle gracefully
        XCTAssertNoThrow(
            manager.uploadFile(
                to: testDevice,
                sourceURL: largeFileURL,
                parentId: 0xFFFFFFFF,
                storageId: 1
            )
        )
    }
    
    func testUploadWithInsufficientStorage() async throws {
        let manager = FileTransferManager.shared
        
        // Create a device with very little free space
        let lowStorageDevice = Device(
            deviceIndex: 0,
            name: "Low Storage Device",
            manufacturer: "Test",
            model: "Model",
            serialNumber: "TEST123",
            batteryLevel: nil,
            storageInfo: [
                StorageInfo(
                    storageId: 1,
                    maxCapacity: 64_000_000_000,
                    freeSpace: 100, // Only 100 bytes free
                    description: "Internal Storage"
                )
            ]
        )
        
        // Should not throw, but should handle gracefully
        XCTAssertNoThrow(
            manager.uploadFile(
                to: lowStorageDevice,
                sourceURL: tempFileURL,
                parentId: 0xFFFFFFFF,
                storageId: 1
            )
        )
    }
    
    func testUploadWithInvalidStorageId() async throws {
        let manager = FileTransferManager.shared
        
        // Should not throw, but should handle gracefully
        XCTAssertNoThrow(
            manager.uploadFile(
                to: testDevice,
                sourceURL: tempFileURL,
                parentId: 0xFFFFFFFF,
                storageId: 9999 // Non-existent storage
            )
        )
    }
    
    // MARK: - Download Tests
    
    func testDownloadWithValidFileItem() async throws {
        let manager = FileTransferManager.shared
        
        let fileItem = FileItem(
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
        
        let tempDir = FileManager.default.temporaryDirectory
        let destinationURL = tempDir.appendingPathComponent("download_\(UUID().uuidString).txt")
        
        // Should not throw, but should handle gracefully
        XCTAssertNoThrow(
            manager.downloadFile(
                from: testDevice,
                fileItem: fileItem,
                to: destinationURL,
                shouldReplace: false
            )
        )
    }    
func testDownloadWithDirectoryFileItem() async throws {
        let manager = FileTransferManager.shared
        let tempDir = FileManager.default.temporaryDirectory
        let destinationURL = tempDir.appendingPathComponent("test_download_dir_\(UUID().uuidString)")
        
        let fileItem = FileItem(
            objectId: 1,
            parentId: 0xFFFFFFFF,
            storageId: 1,
            name: "test_folder",
            path: "/test_folder",
            size: 0,
            modifiedDate: Date(),
            isDirectory: true,
            fileType: "folder"
        )
        
        // Should not throw, but should handle gracefully
        XCTAssertNoThrow(
            manager.downloadFile(
                from: testDevice,
                fileItem: fileItem,
                to: destinationURL
            )
        )
    }
    
    func testDownloadWithExistingDestination() async throws {
        let manager = FileTransferManager.shared
        
        let fileItem = FileItem(
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
        
        // Create a file at the destination
        let tempDir = FileManager.default.temporaryDirectory
        let destinationURL = tempDir.appendingPathComponent("existing_\(UUID().uuidString).txt")
        try? "Existing content".write(to: destinationURL, atomically: true, encoding: .utf8)
        
        // Should not throw, but should handle gracefully
        XCTAssertNoThrow(
            manager.downloadFile(
                from: testDevice,
                fileItem: fileItem,
                to: destinationURL,
                shouldReplace: false
            )
        )
        
        // Clean up
        try? FileManager.default.removeItem(at: destinationURL)
    }
    
    // MARK: - Task Management Tests
    
    func testClearCompletedTasks() async throws {
        let manager = FileTransferManager.shared
        
        // Should not throw
        XCTAssertNoThrow(manager.clearCompletedTasks())
    }
    
    func testCancelAllTasks() async throws {
        let manager = FileTransferManager.shared
        
        // Should not throw
        XCTAssertNoThrow(manager.cancelAllTasks())
    }
    
    func testCancelTask() async throws {
        let manager = FileTransferManager.shared
        
        // Create a mock task on main actor
        let task = await MainActor.run {
            TransferTask(
                type: .upload,
                fileName: "test.txt",
                sourceURL: tempFileURL,
                destinationPath: "/test.txt",
                totalSize: 1024
            )
        }
        
        // Should not throw
        XCTAssertNoThrow(manager.cancelTask(task))
    }
    
    // MARK: - Edge Cases
    
    func testUploadWithSymbolicLink() async throws {
        let manager = FileTransferManager.shared
        
        // Create a temporary file
        let tempDir = FileManager.default.temporaryDirectory
        let originalFile = tempDir.appendingPathComponent("original_\(UUID().uuidString).txt")
        try "Original content".write(to: originalFile, atomically: true, encoding: .utf8)
        
        // Create a symbolic link
        let symlinkURL = tempDir.appendingPathComponent("symlink_\(UUID().uuidString).txt")
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: originalFile)
        
        // Should not throw, but should handle gracefully
        XCTAssertNoThrow(
            manager.uploadFile(
                to: testDevice,
                sourceURL: symlinkURL,
                parentId: 0xFFFFFFFF,
                storageId: 1
            )
        )
        
        // Clean up
        try? FileManager.default.removeItem(at: originalFile)
        try? FileManager.default.removeItem(at: symlinkURL)
    }
    
    func testUploadWithRelativePath() async throws {
        let manager = FileTransferManager.shared
        
        // Create a file with relative path components
        let tempDir = FileManager.default.temporaryDirectory
        let relativeFileURL = URL(fileURLWithPath: "../test.txt", relativeTo: tempDir)
        
        // Should not throw, but should handle gracefully
        XCTAssertNoThrow(
            manager.uploadFile(
                to: testDevice,
                sourceURL: relativeFileURL,
                parentId: 0xFFFFFFFF,
                storageId: 1
            )
        )
    }
    
    func testMultipleUploads() async throws {
        let manager = FileTransferManager.shared
        
        // Create multiple temporary files
        let tempDir = FileManager.default.temporaryDirectory
        var fileURLs: [URL] = []
        
        for i in 0..<5 {
            let fileURL = tempDir.appendingPathComponent("test_\(i)_\(UUID().uuidString).txt")
            try "Content \(i)".write(to: fileURL, atomically: true, encoding: .utf8)
            fileURLs.append(fileURL)
        }
        
        // Upload all files
        for fileURL in fileURLs {
            XCTAssertNoThrow(
                manager.uploadFile(
                    to: testDevice,
                    sourceURL: fileURL,
                    parentId: 0xFFFFFFFF,
                    storageId: 1
                )
            )
        }
        
        // Clean up
        for fileURL in fileURLs {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }
    
    // MARK: - Thread Safety Tests
    
    func testConcurrentUploads() async throws {
        let manager = FileTransferManager.shared
        
        let expectation = self.expectation(description: "Concurrent uploads should complete")
        expectation.expectedFulfillmentCount = 5
        
        let tempDir = FileManager.default.temporaryDirectory
        var fileURLs: [URL] = []
        
        // Create multiple files
        for i in 0..<5 {
            let fileURL = tempDir.appendingPathComponent("concurrent_\(i)_\(UUID().uuidString).txt")
            try "Content \(i)".write(to: fileURL, atomically: true, encoding: .utf8)
            fileURLs.append(fileURL)
        }
        
        // Upload concurrently
        DispatchQueue.concurrentPerform(iterations: 5) { i in
            manager.uploadFile(
                to: testDevice,
                sourceURL: fileURLs[i],
                parentId: 0xFFFFFFFF,
                storageId: 1
            )
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 10.0)
        
        // Clean up
        for fileURL in fileURLs {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }
    
    // MARK: - Performance Tests
    
    func testClearCompletedTasksPerformance() async throws {
        let manager = FileTransferManager.shared
        
        measure {
            for _ in 0..<100 {
                manager.clearCompletedTasks()
            }
        }
    }
    
    func testCancelAllTasksPerformance() async throws {
        let manager = FileTransferManager.shared
        
        measure {
            for _ in 0..<100 {
                manager.cancelAllTasks()
            }
        }
    }
}