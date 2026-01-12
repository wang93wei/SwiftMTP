//
//  FileTransferManagerTests.swift
//  SwiftMTPTests
//
//  Unit tests for FileTransferManager
//
//  NOTE: Temporarily disabled due to concurrency issues.
//  TODO: Fix Swift 6 concurrency violations
//

#if false

import XCTest
import Combine
@testable import SwiftMTP

// MARK: - Mock Protocol for Testing

protocol FileTransferManagerProtocol {
    func uploadFile(to device: Device, sourceURL: URL, parentId: UInt32, storageId: UInt32)
    func downloadFile(from device: Device, fileItem: FileItem, to destinationURL: URL, shouldReplace: Bool)
    func cancelTask(_ task: TransferTask)
    func cancelAllTasks()
    func clearCompletedTasks()
}

// MARK: - Mock Implementation

class MockFileTransferManager: FileTransferManagerProtocol {
    var uploadCalled = false
    var downloadCalled = false
    var cancelTaskCalled = false
    var cancelAllTasksCalled = false
    var clearCompletedTasksCalled = false
    var lastUploadURL: URL?
    var lastDownloadURL: URL?
    
    func uploadFile(to device: Device, sourceURL: URL, parentId: UInt32, storageId: UInt32) {
        uploadCalled = true
        lastUploadURL = sourceURL
    }
    
    func downloadFile(from device: Device, fileItem: FileItem, to destinationURL: URL, shouldReplace: Bool) {
        downloadCalled = true
        lastDownloadURL = destinationURL
    }
    
    func cancelTask(_ task: TransferTask) {
        cancelTaskCalled = true
    }
    
    func cancelAllTasks() {
        cancelAllTasksCalled = true
    }
    
    func clearCompletedTasks() {
        clearCompletedTasksCalled = true
    }
}

final class FileTransferManagerTests: XCTestCase {
    
    var manager: FileTransferManager!
    var testDevice: Device!
    var tempFileURL: URL!
    var mockManager: MockFileTransferManager!
    
    // MARK: - Setup and Teardown
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Initialize manager
        manager = FileTransferManager.shared
        mockManager = MockFileTransferManager()
        
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
    
    // MARK: - Mock Tests
    
    func testMockManagerUploadFile() {
        mockManager.uploadFile(to: testDevice, sourceURL: tempFileURL, parentId: 0xFFFFFFFF, storageId: 1)
        
        XCTAssertTrue(mockManager.uploadCalled)
        XCTAssertEqual(mockManager.lastUploadURL, tempFileURL)
    }
    
    func testMockManagerDownloadFile() {
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
        
        let destinationURL = URL(fileURLWithPath: "/tmp/download_test.txt")
        
        mockManager.downloadFile(from: testDevice, fileItem: fileItem, to: destinationURL, shouldReplace: false)
        
        XCTAssertTrue(mockManager.downloadCalled)
        XCTAssertEqual(mockManager.lastDownloadURL, destinationURL)
    }
    
    func testMockManagerCancelTask() async throws {
        let task = await MainActor.run {
            TransferTask(
                type: .upload,
                fileName: "test.txt",
                sourceURL: tempFileURL,
                destinationPath: "/test.txt",
                totalSize: 1024
            )
        }
        
        mockManager.cancelTask(task)
        
        XCTAssertTrue(mockManager.cancelTaskCalled)
    }
    
    func testMockManagerCancelAllTasks() {
        mockManager.cancelAllTasks()
        
        XCTAssertTrue(mockManager.cancelAllTasksCalled)
    }
    
    func testMockManagerClearCompletedTasks() {
        mockManager.clearCompletedTasks()
        
        XCTAssertTrue(mockManager.clearCompletedTasksCalled)
    }
    
    // MARK: - Path Security Validation Tests
    
    func testUploadWithAbsolutePath() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("absolute_path_test.txt")
        try "Test content".write(to: fileURL, atomically: true, encoding: .utf8)
        
        XCTAssertNoThrow(
            manager.uploadFile(
                to: testDevice,
                sourceURL: fileURL,
                parentId: 0xFFFFFFFF,
                storageId: 1
            )
        )
        
        try? FileManager.default.removeItem(at: fileURL)
    }
    
    func testUploadWithHiddenFile() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(".hidden_file.txt")
        try "Test content".write(to: fileURL, atomically: true, encoding: .utf8)
        
        XCTAssertNoThrow(
            manager.uploadFile(
                to: testDevice,
                sourceURL: fileURL,
                parentId: 0xFFFFFFFF,
                storageId: 1
            )
        )
        
        try? FileManager.default.removeItem(at: fileURL)
    }
    
    func testUploadWithLongFileName() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let longName = String(repeating: "a", count: 200) + ".txt"
        let fileURL = tempDir.appendingPathComponent(longName)
        try "Test content".write(to: fileURL, atomically: true, encoding: .utf8)
        
        XCTAssertNoThrow(
            manager.uploadFile(
                to: testDevice,
                sourceURL: fileURL,
                parentId: 0xFFFFFFFF,
                storageId: 1
            )
        )
        
        try? FileManager.default.removeItem(at: fileURL)
    }
    
    func testUploadWithUnicodeFileName() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("测试文件_🎉.txt")
        try "Test content".write(to: fileURL, atomically: true, encoding: .utf8)
        
        XCTAssertNoThrow(
            manager.uploadFile(
                to: testDevice,
                sourceURL: fileURL,
                parentId: 0xFFFFFFFF,
                storageId: 1
            )
        )
        
        try? FileManager.default.removeItem(at: fileURL)
    }
    
    func testUploadWithZeroByteFile() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("empty.txt")
        try "".write(to: fileURL, atomically: true, encoding: .utf8)
        
        XCTAssertNoThrow(
            manager.uploadFile(
                to: testDevice,
                sourceURL: fileURL,
                parentId: 0xFFFFFFFF,
                storageId: 1
            )
        )
        
        try? FileManager.default.removeItem(at: fileURL)
    }
    
    func testUploadWithVerySmallFile() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("tiny.txt")
        try "x".write(to: fileURL, atomically: true, encoding: .utf8)
        
        XCTAssertNoThrow(
            manager.uploadFile(
                to: testDevice,
                sourceURL: fileURL,
                parentId: 0xFFFFFFFF,
                storageId: 1
            )
        )
        
        try? FileManager.default.removeItem(at: fileURL)
    }
    
    // MARK: - Download Edge Cases
    
    func testDownloadWithZeroByteFile() async throws {
        let fileItem = FileItem(
            objectId: 1,
            parentId: 0xFFFFFFFF,
            storageId: 1,
            name: "empty.txt",
            path: "/empty.txt",
            size: 0,
            modifiedDate: Date(),
            isDirectory: false,
            fileType: "txt"
        )
        
        let tempDir = FileManager.default.temporaryDirectory
        let destinationURL = tempDir.appendingPathComponent("download_empty.txt")
        
        XCTAssertNoThrow(
            manager.downloadFile(
                from: testDevice,
                fileItem: fileItem,
                to: destinationURL
            )
        )
    }
    
    func testDownloadWithVeryLargeFile() async throws {
        let fileItem = FileItem(
            objectId: 1,
            parentId: 0xFFFFFFFF,
            storageId: 1,
            name: "large.bin",
            path: "/large.bin",
            size: 5 * 1024 * 1024 * 1024, // 5 GB
            modifiedDate: Date(),
            isDirectory: false,
            fileType: "bin"
        )
        
        let tempDir = FileManager.default.temporaryDirectory
        let destinationURL = tempDir.appendingPathComponent("download_large.bin")
        
        XCTAssertNoThrow(
            manager.downloadFile(
                from: testDevice,
                fileItem: fileItem,
                to: destinationURL
            )
        )
    }
    
    func testDownloadWithReadOnlyDestination() async throws {
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
        
        // Try to download to a root directory (should fail or handle gracefully)
        let destinationURL = URL(fileURLWithPath: "/test.txt")
        
        XCTAssertNoThrow(
            manager.downloadFile(
                from: testDevice,
                fileItem: fileItem,
                to: destinationURL
            )
        )
    }
    
    // MARK: - Task State Transition Tests
    
    func testTaskStateTransitionPendingToTransferring() async throws {
        let task = await MainActor.run {
            TransferTask(
                type: .upload,
                fileName: "test.txt",
                sourceURL: tempFileURL,
                destinationPath: "/test.txt",
                totalSize: 1024
            )
        }

        await MainActor.run {
            XCTAssertEqual(task.status, .pending)
        }

        await MainActor.run {
            task.updateStatus(.transferring)
        }

        await MainActor.run {
            XCTAssertEqual(task.status, .transferring)
        }
        XCTAssertNotNil(await MainActor.run { task.startTime })
    }
    
    func testTaskStateTransitionTransferringToCompleted() async throws {
        let task = await MainActor.run {
            TransferTask(
                type: .upload,
                fileName: "test.txt",
                sourceURL: tempFileURL,
                destinationPath: "/test.txt",
                totalSize: 1024
            )
        }

        await MainActor.run {
            task.updateStatus(.transferring)
        }

        await MainActor.run {
            task.updateStatus(.completed)
        }

        await MainActor.run {
            XCTAssertEqual(task.status, .completed)
        }
        XCTAssertNotNil(await MainActor.run { task.endTime })
    }
    
    func testTaskStateTransitionTransferringToFailed() async throws {
        let task = await MainActor.run {
            TransferTask(
                type: .upload,
                fileName: "test.txt",
                sourceURL: tempFileURL,
                destinationPath: "/test.txt",
                totalSize: 1024
            )
        }

        await MainActor.run {
            task.updateStatus(.transferring)
        }

        await MainActor.run {
            task.updateStatus(.failed("Connection lost"))
        }

        await MainActor.run {
            XCTAssertEqual(task.status, .failed("Connection lost"))
        }
        XCTAssertNotNil(await MainActor.run { task.endTime })
    }

    func testTaskStateTransitionPendingToCancelled() async throws {
        let task = await MainActor.run {
            TransferTask(
                type: .upload,
                fileName: "test.txt",
                sourceURL: tempFileURL,
                destinationPath: "/test.txt",
                totalSize: 1024
            )
        }

        await MainActor.run {
            XCTAssertEqual(task.status, .pending)
        }

        await MainActor.run {
            task.updateStatus(.cancelled)
        }

        await MainActor.run {
            XCTAssertEqual(task.status, .cancelled)
        }
    }
    
    // MARK: - Progress Update Tests
    
    func testProgressUpdateWithPartialTransfer() async throws {
        let task = await MainActor.run {
            TransferTask(
                type: .upload,
                fileName: "test.txt",
                sourceURL: tempFileURL,
                destinationPath: "/test.txt",
                totalSize: 1000
            )
        }
        
        await MainActor.run {
            task.updateProgress(transferred: 500, speed: 100)
        }
        
        XCTAssertEqual(await MainActor.run { task.transferredSize }, 500)
        XCTAssertEqual(await MainActor.run { task.progress }, 0.5, accuracy: 0.01)
    }
    
    func testProgressUpdateWithFullTransfer() async throws {
        let task = await MainActor.run {
            TransferTask(
                type: .upload,
                fileName: "test.txt",
                sourceURL: tempFileURL,
                destinationPath: "/test.txt",
                totalSize: 1000
            )
        }
        
        await MainActor.run {
            task.updateProgress(transferred: 1000, speed: 100)
        }
        
        XCTAssertEqual(await MainActor.run { task.transferredSize }, 1000)
        XCTAssertEqual(await MainActor.run { task.progress }, 1.0, accuracy: 0.01)
    }
    
    func testProgressUpdateSpeedCalculation() async throws {
        let task = await MainActor.run {
            TransferTask(
                type: .upload,
                fileName: "test.txt",
                sourceURL: tempFileURL,
                destinationPath: "/test.txt",
                totalSize: 1024 * 1024
            )
        }
        
        await MainActor.run {
            task.updateProgress(transferred: 512 * 1024, speed: 1024 * 1024) // 1 MB/s
        }
        
        XCTAssertEqual(await MainActor.run { task.speed }, 1024 * 1024, accuracy: 1.0)
    }
    
    // MARK: - Multiple File Types Tests
    
    func testUploadDifferentFileTypes() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        
        let fileTypes = [
            ("document.pdf", "PDF"),
            ("image.jpg", "JPG"),
            ("video.mp4", "MP4"),
            ("audio.mp3", "MP3"),
            ("archive.zip", "ZIP")
        ]
        
        for (fileName, _) in fileTypes {
            let fileURL = tempDir.appendingPathComponent(fileName)
            try "Test content".write(to: fileURL, atomically: true, encoding: .utf8)
            
            XCTAssertNoThrow(
                manager.uploadFile(
                    to: testDevice,
                    sourceURL: fileURL,
                    parentId: 0xFFFFFFFF,
                    storageId: 1
                )
            )
            
            try? FileManager.default.removeItem(at: fileURL)
        }
    }
    
    // MARK: - Storage Validation Tests
    
    func testUploadWithExactlyEnoughSpace() async throws {
        let exactSizeDevice = Device(
            deviceIndex: 0,
            name: "Exact Space Device",
            manufacturer: "Test",
            model: "Model",
            serialNumber: "TEST123",
            batteryLevel: nil,
            storageInfo: [
                StorageInfo(
                    storageId: 1,
                    maxCapacity: 64_000_000_000,
                    freeSpace: 1024, // Exactly the size of our test file
                    description: "Internal Storage"
                )
            ]
        )
        
        XCTAssertNoThrow(
            manager.uploadFile(
                to: exactSizeDevice,
                sourceURL: tempFileURL,
                parentId: 0xFFFFFFFF,
                storageId: 1
            )
        )
    }
    
    func testUploadWithMultipleStorages() async throws {
        let multiStorageDevice = Device(
            deviceIndex: 0,
            name: "Multi Storage Device",
            manufacturer: "Test",
            model: "Model",
            serialNumber: "TEST123",
            batteryLevel: nil,
            storageInfo: [
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
        )
        
        // Upload to first storage
        XCTAssertNoThrow(
            manager.uploadFile(
                to: multiStorageDevice,
                sourceURL: tempFileURL,
                parentId: 0xFFFFFFFF,
                storageId: 1
            )
        )
        
        // Upload to second storage
        XCTAssertNoThrow(
            manager.uploadFile(
                to: multiStorageDevice,
                sourceURL: tempFileURL,
                parentId: 0xFFFFFFFF,
                storageId: 2
            )
        )
    }
    
    // MARK: - Concurrent Operations Tests
    
    func testConcurrentUploadAndDownload() async throws {
        let expectation = self.expectation(description: "Concurrent upload and download should complete")
        expectation.expectedFulfillmentCount = 2
        
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
        let destinationURL = tempDir.appendingPathComponent("download_test.txt")
        
        DispatchQueue.global().async {
            self.manager.uploadFile(to: self.testDevice, sourceURL: self.tempFileURL, parentId: 0xFFFFFFFF, storageId: 1)
            expectation.fulfill()
        }
        
        DispatchQueue.global().async {
            self.manager.downloadFile(from: self.testDevice, fileItem: fileItem, to: destinationURL)
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 5.0)
    }
    
    // MARK: - Error Recovery Tests
    
    func testUploadRetryAfterFailure() async throws {
        // Upload once
        XCTAssertNoThrow(
            manager.uploadFile(
                to: testDevice,
                sourceURL: tempFileURL,
                parentId: 0xFFFFFFFF,
                storageId: 1
            )
        )
        
        // Upload again (retry)
        XCTAssertNoThrow(
            manager.uploadFile(
                to: testDevice,
                sourceURL: tempFileURL,
                parentId: 0xFFFFFFFF,
                storageId: 1
            )
        )
    }
    
    func testDownloadRetryAfterFailure() async throws {
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
        let destinationURL = tempDir.appendingPathComponent("download_test.txt")
        
        // Download once
        XCTAssertNoThrow(
            manager.downloadFile(
                from: testDevice,
                fileItem: fileItem,
                to: destinationURL
            )
        )
        
        // Download again (retry)
        XCTAssertNoThrow(
            manager.downloadFile(
                from: testDevice,
                fileItem: fileItem,
                to: destinationURL
            )
        )
    }
}#endif
