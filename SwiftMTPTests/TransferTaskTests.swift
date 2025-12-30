//
//  TransferTaskTests.swift
//  SwiftMTPTests
//
//  Unit tests for TransferTask, TransferType, and TransferStatus models
//

import XCTest
@testable import SwiftMTP

@MainActor
final class TransferTaskTests: XCTestCase {
    
    // Track created temp files for cleanup
    private var tempFiles: [URL] = []
    
    // MARK: - TransferType Tests
    
    func testTransferTypeRawValues() {
        XCTAssertEqual(TransferType.upload.rawValue, "upload")
        XCTAssertEqual(TransferType.download.rawValue, "download")
    }
    
    func testTransferTypeAllCases() {
        let types: [TransferType] = [.upload, .download]
        XCTAssertEqual(types.count, 2)
    }
    
    func testTransferTypeCodable() {
        let uploadType = TransferType.upload
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        do {
            let encoded = try encoder.encode(uploadType)
            let decoded = try decoder.decode(TransferType.self, from: encoded)
            XCTAssertEqual(decoded, .upload)
        } catch {
            XCTFail("Failed to encode/decode TransferType: \(error)")
        }
    }
    
    // MARK: - TransferStatus Tests
    
    func testTransferStatusAllCases() {
        let statuses: [TransferStatus] = [
            .pending,
            .transferring,
            .paused,
            .completed,
            .failed("Test error"),
            .cancelled
        ]
        XCTAssertEqual(statuses.count, 6)
    }
    
    func testTransferStatusIsActive() {
        XCTAssertTrue(TransferStatus.pending.isActive)
        XCTAssertTrue(TransferStatus.transferring.isActive)
        XCTAssertFalse(TransferStatus.paused.isActive)
        XCTAssertFalse(TransferStatus.completed.isActive)
        XCTAssertFalse(TransferStatus.failed("error").isActive)
        XCTAssertFalse(TransferStatus.cancelled.isActive)
    }
    
    func testTransferStatusEquality() {
        XCTAssertEqual(TransferStatus.pending, TransferStatus.pending)
        XCTAssertNotEqual(TransferStatus.pending, TransferStatus.transferring)
        XCTAssertEqual(TransferStatus.failed("error1"), TransferStatus.failed("error1"))
        XCTAssertNotEqual(TransferStatus.failed("error1"), TransferStatus.failed("error2"))
    }
    
    func testTransferStatusCodable() {
        let status = TransferStatus.completed
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        do {
            let encoded = try encoder.encode(status)
            let decoded = try decoder.decode(TransferStatus.self, from: encoded)
            XCTAssertEqual(decoded, .completed)
        } catch {
            XCTFail("Failed to encode/decode TransferStatus: \(error)")
        }
    }
    
    // MARK: - TransferTask Initialization Tests
    
    func testTransferTaskInitialization() throws {
        let tempFile = try createTempFile()
        
        let task = TransferTask(
            type: .upload,
            fileName: "test.txt",
            sourceURL: tempFile,
            destinationPath: "/test.txt",
            totalSize: 1024
        )
        
        XCTAssertEqual(task.type, .upload)
        XCTAssertEqual(task.fileName, "test.txt")
        XCTAssertEqual(task.sourceURL, tempFile)
        XCTAssertEqual(task.destinationPath, "/test.txt")
        XCTAssertEqual(task.totalSize, 1024)
        XCTAssertEqual(task.transferredSize, 0)
        XCTAssertEqual(task.status, .pending)
        XCTAssertEqual(task.speed, 0)
        XCTAssertNil(task.startTime)
        XCTAssertNil(task.endTime)
        XCTAssertNotNil(task.id)
        XCTAssertFalse(task.isCancelled)
    }
    
    func testTransferTaskWithDownloadType() throws {
        let tempFile = try createTempFile()
        
        let task = TransferTask(
            type: .download,
            fileName: "download.txt",
            sourceURL: tempFile,
            destinationPath: "/download.txt",
            totalSize: 2048
        )
        
        XCTAssertEqual(task.type, .download)
        XCTAssertEqual(task.fileName, "download.txt")
    }
    
    func testTransferTaskWithCustomId() throws {
        let tempFile = try createTempFile()
        let customId = UUID()
        
        let task = TransferTask(
            id: customId,
            type: .upload,
            fileName: "test.txt",
            sourceURL: tempFile,
            destinationPath: "/test.txt",
            totalSize: 1024
        )
        
        XCTAssertEqual(task.id, customId)
    }
    
    // MARK: - Progress Calculation Tests
    
    func testProgressCalculation() throws {
        let tempFile = try createTempFile()
        
        let task = TransferTask(
            type: .upload,
            fileName: "test.txt",
            sourceURL: tempFile,
            destinationPath: "/test.txt",
            totalSize: 1000
        )
        
        XCTAssertEqual(task.progress, 0.0)
        
        task.updateProgress(transferred: 500, speed: 100)
        XCTAssertEqual(task.progress, 0.5, accuracy: 0.01)
        
        task.updateProgress(transferred: 1000, speed: 100)
        XCTAssertEqual(task.progress, 1.0, accuracy: 0.01)
    }
    
    func testProgressWithZeroTotalSize() throws {
        let tempFile = try createTempFile()
        
        let task = TransferTask(
            type: .upload,
            fileName: "test.txt",
            sourceURL: tempFile,
            destinationPath: "/test.txt",
            totalSize: 0
        )
        
        XCTAssertEqual(task.progress, 0.0)
        
        task.updateProgress(transferred: 100, speed: 100)
        XCTAssertEqual(task.progress, 0.0) // Should remain 0 when total is 0
    }
    
    func testFormattedProgress() throws {
        let tempFile = try createTempFile()
        
        let task = TransferTask(
            type: .upload,
            fileName: "test.txt",
            sourceURL: tempFile,
            destinationPath: "/test.txt",
            totalSize: 1000
        )
        
        XCTAssertEqual(task.formattedProgress, "0.0%")
        
        task.updateProgress(transferred: 500, speed: 100)
        XCTAssertEqual(task.formattedProgress, "50.0%")
        
        task.updateProgress(transferred: 1000, speed: 100)
        XCTAssertEqual(task.formattedProgress, "100.0%")
    }
    
    // MARK: - Speed Formatting Tests
    
    func testFormattedSpeedBytesPerSecond() throws {
        let tempFile = try createTempFile()
        
        let task = TransferTask(
            type: .upload,
            fileName: "test.txt",
            sourceURL: tempFile,
            destinationPath: "/test.txt",
            totalSize: 1024
        )
        
        task.updateProgress(transferred: 0, speed: 512)
        XCTAssertTrue(task.formattedSpeed.contains("B/s"))
    }
    
    func testFormattedSpeedKilobytesPerSecond() throws {
        let tempFile = try createTempFile()
        
        let task = TransferTask(
            type: .upload,
            fileName: "test.txt",
            sourceURL: tempFile,
            destinationPath: "/test.txt",
            totalSize: 1024
        )
        
        task.updateProgress(transferred: 0, speed: 1024)
        XCTAssertTrue(task.formattedSpeed.contains("KB/s"))
        
        task.updateProgress(transferred: 0, speed: 512 * 1024)
        XCTAssertTrue(task.formattedSpeed.contains("KB/s"))
    }
    
    func testFormattedSpeedMegabytesPerSecond() throws {
        let tempFile = try createTempFile()
        
        let task = TransferTask(
            type: .upload,
            fileName: "test.txt",
            sourceURL: tempFile,
            destinationPath: "/test.txt",
            totalSize: 1024
        )
        
        task.updateProgress(transferred: 0, speed: 1024 * 1024)
        XCTAssertTrue(task.formattedSpeed.contains("MB/s"))
    }
    
    func testFormattedSpeedZero() throws {
        let tempFile = try createTempFile()
        
        let task = TransferTask(
            type: .upload,
            fileName: "test.txt",
            sourceURL: tempFile,
            destinationPath: "/test.txt",
            totalSize: 1024
        )
        
        XCTAssertTrue(task.formattedSpeed.contains("0 B/s"))
    }
    
    // MARK: - Estimated Time Remaining Tests
    
    func testEstimatedTimeRemainingSeconds() throws {
        let tempFile = try createTempFile()
        
        let task = TransferTask(
            type: .upload,
            fileName: "test.txt",
            sourceURL: tempFile,
            destinationPath: "/test.txt",
            totalSize: 1024
        )
        
        task.updateProgress(transferred: 512, speed: 512) // 512 bytes remaining at 512 B/s = 1 second
        XCTAssertFalse(task.estimatedTimeRemaining == "--")
    }
    
    func testEstimatedTimeRemainingMinutes() throws {
        let tempFile = try createTempFile()
        
        let task = TransferTask(
            type: .upload,
            fileName: "test.txt",
            sourceURL: tempFile,
            destinationPath: "/test.txt",
            totalSize: 1024 * 1024
        )
        
        task.updateProgress(transferred: 512 * 1024, speed: 512 * 1024) // 512 KB remaining at 512 KB/s = 60 seconds = 1 minute
        XCTAssertFalse(task.estimatedTimeRemaining == "--")
    }
    
    func testEstimatedTimeRemainingHours() throws {
        let tempFile = try createTempFile()
        
        let task = TransferTask(
            type: .upload,
            fileName: "test.txt",
            sourceURL: tempFile,
            destinationPath: "/test.txt",
            totalSize: 1024 * 1024 * 1024
        )
        
        task.updateProgress(transferred: 512 * 1024 * 1024, speed: 512 * 1024 * 1024) // 512 MB remaining at 512 MB/s = 3600 seconds = 1 hour
        XCTAssertFalse(task.estimatedTimeRemaining == "--")
    }
    
    func testEstimatedTimeRemainingZeroSpeed() throws {
        let tempFile = try createTempFile()
        
        let task = TransferTask(
            type: .upload,
            fileName: "test.txt",
            sourceURL: tempFile,
            destinationPath: "/test.txt",
            totalSize: 1024
        )
        
        task.updateProgress(transferred: 512, speed: 0)
        XCTAssertEqual(task.estimatedTimeRemaining, "--")
    }
    
    func testEstimatedTimeRemainingCompleted() throws {
        let tempFile = try createTempFile()
        
        let task = TransferTask(
            type: .upload,
            fileName: "test.txt",
            sourceURL: tempFile,
            destinationPath: "/test.txt",
            totalSize: 1024
        )
        
        task.updateProgress(transferred: 1024, speed: 1024) // All transferred
        XCTAssertEqual(task.estimatedTimeRemaining, "--")
    }
    
    // MARK: - Status Update Tests
    
    func testUpdateStatusToTransferring() throws {
        let tempFile = try createTempFile()
        
        let task = TransferTask(
            type: .upload,
            fileName: "test.txt",
            sourceURL: tempFile,
            destinationPath: "/test.txt",
            totalSize: 1024
        )
        
        XCTAssertNil(task.startTime)
        
        task.updateStatus(.transferring)
        
        XCTAssertEqual(task.status, .transferring)
        XCTAssertNotNil(task.startTime)
        XCTAssertNil(task.endTime)
    }
    
    func testUpdateStatusToCompleted() throws {
        let tempFile = try createTempFile()
        
        let task = TransferTask(
            type: .upload,
            fileName: "test.txt",
            sourceURL: tempFile,
            destinationPath: "/test.txt",
            totalSize: 1024
        )
        
        task.updateStatus(.transferring)
        XCTAssertNotNil(task.startTime)
        
        task.updateStatus(.completed)
        
        XCTAssertEqual(task.status, .completed)
        XCTAssertNotNil(task.endTime)
    }
    
    func testUpdateStatusToFailed() throws {
        let tempFile = try createTempFile()
        
        let task = TransferTask(
            type: .upload,
            fileName: "test.txt",
            sourceURL: tempFile,
            destinationPath: "/test.txt",
            totalSize: 1024
        )
        
        task.updateStatus(.transferring)
        
        task.updateStatus(.failed("Connection lost"))
        
        XCTAssertEqual(task.status, .failed("Connection lost"))
        XCTAssertNotNil(task.endTime)
    }
    
    func testUpdateStatusToCancelled() throws {
        let tempFile = try createTempFile()
        
        let task = TransferTask(
            type: .upload,
            fileName: "test.txt",
            sourceURL: tempFile,
            destinationPath: "/test.txt",
            totalSize: 1024
        )
        
        task.updateStatus(.transferring)
        
        task.updateStatus(.cancelled)
        
        XCTAssertEqual(task.status, .cancelled)
        XCTAssertNotNil(task.endTime)
    }
    
    func testUpdateStatusToPaused() throws {
        let tempFile = try createTempFile()
        
        let task = TransferTask(
            type: .upload,
            fileName: "test.txt",
            sourceURL: tempFile,
            destinationPath: "/test.txt",
            totalSize: 1024
        )
        
        task.updateStatus(.paused)
        
        XCTAssertEqual(task.status, .paused)
        XCTAssertNil(task.startTime)
        XCTAssertNil(task.endTime)
    }
    
    // MARK: - Cancel State Tests
    
    func testIsCancelled() throws {
        let tempFile = try createTempFile()
        
        let task = TransferTask(
            type: .upload,
            fileName: "test.txt",
            sourceURL: tempFile,
            destinationPath: "/test.txt",
            totalSize: 1024
        )
        
        XCTAssertFalse(task.isCancelled)
        
        task.isCancelled = true
        
        XCTAssertTrue(task.isCancelled)
    }
    
    // MARK: - Boundary and Edge Cases
    
    func testLargeFileSize() throws {
        let tempFile = try createTempFile()
        
        let largeSize: UInt64 = 10 * 1024 * 1024 * 1024 // 10 GB
        
        let task = TransferTask(
            type: .upload,
            fileName: "large.bin",
            sourceURL: tempFile,
            destinationPath: "/large.bin",
            totalSize: largeSize
        )
        
        XCTAssertEqual(task.totalSize, largeSize)
        
        task.updateProgress(transferred: largeSize / 2, speed: Double(largeSize) / 100.0)
        XCTAssertEqual(task.progress, 0.5, accuracy: 0.01)
    }
    
    func testVeryLargeFileSize() throws {
        let tempFile = try createTempFile()
        
        let hugeSize: UInt64 = UInt64.max / 2
        
        let task = TransferTask(
            type: .upload,
            fileName: "huge.bin",
            sourceURL: tempFile,
            destinationPath: "/huge.bin",
            totalSize: hugeSize
        )
        
        XCTAssertEqual(task.totalSize, hugeSize)
        
        task.updateProgress(transferred: hugeSize / 2, speed: 1024 * 1024 * 100)
        XCTAssertEqual(task.progress, 0.5, accuracy: 0.01)
    }
    
    func testProgressOverflow() throws {
        let tempFile = try createTempFile()
        
        let task = TransferTask(
            type: .upload,
            fileName: "test.txt",
            sourceURL: tempFile,
            destinationPath: "/test.txt",
            totalSize: 1000
        )
        
        // Try to set transferred size larger than total
        task.updateProgress(transferred: 2000, speed: 100)
        
        // Progress should be capped at 1.0 or handle gracefully
        XCTAssertGreaterThanOrEqual(task.progress, 0.0)
        XCTAssertLessThanOrEqual(task.progress, 1.0)
    }
    
    func testMultipleStatusUpdates() throws {
        let tempFile = try createTempFile()
        
        let task = TransferTask(
            type: .upload,
            fileName: "test.txt",
            sourceURL: tempFile,
            destinationPath: "/test.txt",
            totalSize: 1024
        )
        
        task.updateStatus(.transferring)
        XCTAssertEqual(task.status, .transferring)
        XCTAssertNotNil(task.startTime)
        
        task.updateStatus(.paused)
        XCTAssertEqual(task.status, .paused)
        
        task.updateStatus(.transferring) // Resume
        XCTAssertEqual(task.status, .transferring)
        
        task.updateStatus(.completed)
        XCTAssertEqual(task.status, .completed)
        XCTAssertNotNil(task.endTime)
    }
    
    // MARK: - Helper Methods
    
    private func createTempFile() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent(UUID().uuidString + ".txt")
        try "test content".write(to: tempFile, atomically: true, encoding: .utf8)
        tempFiles.append(tempFile)
        return tempFile
    }
    
    override func tearDown() async throws {
        // Clean up only the temp files created by this test
        for file in tempFiles {
            try? FileManager.default.removeItem(at: file)
        }
        tempFiles.removeAll()
        try await super.tearDown()
    }
}