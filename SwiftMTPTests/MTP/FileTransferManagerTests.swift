import Foundation
import XCTest
@testable import SwiftMTP

@MainActor
final class FileTransferManagerTests: XCTestCase {
    func testDownloadSubmissionBindsTypedIdentityAndCompletesOnce() async throws {
        let coordinator = FakeTransferCoordinator()
        let finalizer = TransferFinalizerDouble()
        let started = expectation(description: "download started")
        let release = DispatchSemaphore(value: 0)
        coordinator.downloadHandler = { _, _, _, progress, _ in
            started.fulfill()
            progress(2)
            progress(4)
            release.wait()
        }
        let manager = FileTransferManager(
            coordinator: coordinator,
            completionFinalizer: finalizer
        )
        let device = try makeTransferDevice()
        let file = try makeTransferFile(size: 4)
        let destination = temporaryURL("download.bin")

        let task = try manager.downloadFile(
            from: device,
            fileItem: file,
            to: destination,
            shouldReplace: true
        )

        XCTAssertEqual(task.status, .pending)
        XCTAssertEqual(manager.activeTasks.map(\.id), [task.id])
        await fulfillment(of: [started], timeout: 2)
        await waitUntil { task.status == .transferring && task.transferredSize == 4 }
        release.signal()
        await waitUntil { task.status == .completed }

        XCTAssertEqual(coordinator.downloadCalls.count, 1)
        XCTAssertEqual(coordinator.downloadCalls.first?.appDeviceID, device.id)
        XCTAssertEqual(coordinator.downloadCalls.first?.deviceID, device.mtpIdentity.deviceID)
        XCTAssertEqual(coordinator.downloadCalls.first?.request.objectID, file.objectID)
        XCTAssertEqual(coordinator.downloadCalls.first?.request.expectedSize, 4)
        XCTAssertEqual(
            coordinator.downloadCalls.first?.request.replacementPolicy,
            .replaceExisting
        )
        XCTAssertTrue(manager.activeTasks.isEmpty)
        XCTAssertEqual(manager.completedTasks.map(\.id), [task.id])
        XCTAssertTrue(finalizer.events.isEmpty)
    }

    func testUploadSubmissionUsesTypedStorageParentAndActualSize() async throws {
        let coordinator = FakeTransferCoordinator()
        let finalizer = TransferFinalizerDouble()
        coordinator.uploadHandler = { _, _, _, progress, _ in
            progress(3)
        }
        let manager = FileTransferManager(
            coordinator: coordinator,
            completionFinalizer: finalizer
        )
        let device = try makeTransferDevice()
        let source = temporaryURL("upload.bin")
        try Data([1, 2, 3]).write(to: source)

        let task = try manager.uploadFile(
            to: device,
            sourceURL: source,
            parentId: MTPObjectID.root.rawValue,
            storageId: device.storageInfo[0].storageID.rawValue
        )
        await waitUntil { task.status == .completed }

        let call = try XCTUnwrap(coordinator.uploadCalls.first)
        XCTAssertEqual(call.appDeviceID, device.id)
        XCTAssertEqual(call.deviceID, device.mtpIdentity.deviceID)
        XCTAssertEqual(call.request.storageID, device.storageInfo[0].storageID)
        XCTAssertEqual(call.request.parentID, .root)
        XCTAssertEqual(call.request.sourceURL, source)
        XCTAssertEqual(call.request.name, "upload.bin")
        XCTAssertEqual(call.request.size, 3)
        XCTAssertEqual(task.transferredSize, 3)
        XCTAssertEqual(manager.completedTasks.map(\.id), [task.id])
        XCTAssertEqual(
            finalizer.events,
            [
                TransferCompletionEvent(
                    appDeviceID: device.id,
                    storageID: device.storageInfo[0].storageID,
                    parentID: .root,
                    outcome: .completed,
                    remoteMutation: true
                ),
            ]
        )
    }

    func testSubmissionRejectionsAreTypedAndCreateNoTask() throws {
        let coordinator = FakeTransferCoordinator()
        let manager = FileTransferManager(coordinator: coordinator)
        let device = try makeTransferDevice()
        let missing = temporaryURL("missing.bin")

        XCTAssertThrowsError(
            try manager.uploadFile(
                to: device,
                sourceURL: missing,
                parentId: MTPObjectID.root.rawValue,
                storageId: device.storageInfo[0].storageID.rawValue
            )
        ) {
            XCTAssertTrue($0 is MTPCoreError)
        }
        XCTAssertThrowsError(
            try manager.downloadFile(
                from: device,
                fileItem: try makeTransferFile(isDirectory: true),
                to: temporaryURL("folder")
            )
        ) {
            XCTAssertEqual(
                $0 as? MTPCoreError,
                .invalidInput("download source must be a file")
            )
        }
        XCTAssertTrue(manager.activeTasks.isEmpty)
        XCTAssertTrue(manager.completedTasks.isEmpty)
        XCTAssertTrue(coordinator.downloadCalls.isEmpty)
        XCTAssertTrue(coordinator.uploadCalls.isEmpty)
    }

    func testProviderFailureMovesTaskOnceWithoutReplay() async throws {
        let coordinator = FakeTransferCoordinator()
        coordinator.downloadHandler = { _, _, _, _, _ in
            throw MTPCoreError.timeout
        }
        let manager = FileTransferManager(coordinator: coordinator)

        let task = try manager.downloadFile(
            from: try makeTransferDevice(),
            fileItem: try makeTransferFile(),
            to: temporaryURL("failed.bin")
        )
        await waitUntil {
            if case .failed = task.status { return true }
            return false
        }

        XCTAssertEqual(coordinator.downloadCalls.count, 1)
        XCTAssertTrue(manager.activeTasks.isEmpty)
        XCTAssertEqual(manager.completedTasks.map(\.id), [task.id])
    }

    func testQueuedCancellationIsIdempotentAndNeverReachesProvider() async throws {
        let coordinator = FakeTransferCoordinator()
        let queue = DispatchQueue(label: "FileTransferManagerTests.suspended")
        queue.suspend()
        let manager = FileTransferManager(coordinator: coordinator, transferQueue: queue)
        let task = try manager.downloadFile(
            from: try makeTransferDevice(),
            fileItem: try makeTransferFile(),
            to: temporaryURL("queued.bin")
        )

        manager.cancelTask(task)
        manager.cancelTask(task)
        await waitUntil { task.status == .cancelled }
        XCTAssertEqual(task.status, .cancelled)
        XCTAssertTrue(manager.activeTasks.isEmpty)
        XCTAssertEqual(manager.completedTasks.map(\.id), [task.id])

        queue.resume()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(coordinator.downloadCalls.isEmpty)
        XCTAssertEqual(manager.completedTasks.map(\.id), [task.id])
    }

    func testRunningCancellationCancelsProviderTokenAndWinsTerminalRace() async throws {
        let coordinator = FakeTransferCoordinator()
        let finalizer = TransferFinalizerDouble()
        let started = expectation(description: "upload started")
        let release = DispatchSemaphore(value: 0)
        coordinator.uploadHandler = { _, _, _, _, cancellation in
            started.fulfill()
            release.wait()
            try cancellation.throwIfCancelled()
        }
        let manager = FileTransferManager(
            coordinator: coordinator,
            completionFinalizer: finalizer
        )
        let source = temporaryURL("running.bin")
        try Data([1]).write(to: source)
        let device = try makeTransferDevice()
        let task = try manager.uploadFile(
            to: device,
            sourceURL: source,
            parentId: MTPObjectID.root.rawValue,
            storageId: device.storageInfo[0].storageID.rawValue
        )
        await fulfillment(of: [started], timeout: 2)

        manager.cancelTask(task)
        manager.cancelTask(task)
        release.signal()
        await waitUntil { task.status == .cancelled }

        XCTAssertTrue(coordinator.uploadCalls.first?.cancellation.isCancelled == true)
        XCTAssertEqual(coordinator.uploadCalls.count, 1)
        XCTAssertTrue(manager.activeTasks.isEmpty)
        XCTAssertEqual(manager.completedTasks.map(\.id), [task.id])
        XCTAssertEqual(finalizer.events.count, 1)
        XCTAssertEqual(finalizer.events.first?.outcome, .cancelled)
        XCTAssertEqual(finalizer.events.first?.remoteMutation, true)
    }

    func testUploadFailureClassifiesWhetherRemoteMutationMayHaveOccurred() async throws {
        let device = try makeTransferDevice()

        let localCoordinator = FakeTransferCoordinator()
        localCoordinator.uploadHandler = { _, _, _, _, _ in
            throw MTPCoreError.localFileIO("/private/sensitive/source.bin")
        }
        let localFinalizer = TransferFinalizerDouble()
        let localManager = FileTransferManager(
            coordinator: localCoordinator,
            completionFinalizer: localFinalizer
        )
        let localSource = temporaryURL("local-failure.bin")
        try Data([1]).write(to: localSource)
        let localTask = try localManager.uploadFile(
            to: device,
            sourceURL: localSource,
            parentId: MTPObjectID.root.rawValue,
            storageId: device.storageInfo[0].storageID.rawValue
        )
        await waitUntil {
            if case .failed = localTask.status { return true }
            return false
        }

        XCTAssertEqual(localFinalizer.events.count, 1)
        XCTAssertEqual(localFinalizer.events.first?.outcome, .failed)
        XCTAssertEqual(localFinalizer.events.first?.remoteMutation, false)
        if case .failed(let message) = localTask.status {
            XCTAssertEqual(message, L10n.FileTransfer.uploadFailed)
            XCTAssertFalse(message.contains("sensitive"))
        } else {
            XCTFail("local provider failure must be terminal")
        }

        let timeoutCoordinator = FakeTransferCoordinator()
        timeoutCoordinator.uploadHandler = { _, _, _, _, _ in
            throw MTPCoreError.timeout
        }
        let timeoutFinalizer = TransferFinalizerDouble()
        let timeoutManager = FileTransferManager(
            coordinator: timeoutCoordinator,
            completionFinalizer: timeoutFinalizer
        )
        let timeoutSource = temporaryURL("timeout.bin")
        try Data([1]).write(to: timeoutSource)
        let timeoutTask = try timeoutManager.uploadFile(
            to: device,
            sourceURL: timeoutSource,
            parentId: MTPObjectID.root.rawValue,
            storageId: device.storageInfo[0].storageID.rawValue
        )
        await waitUntil {
            if case .failed = timeoutTask.status { return true }
            return false
        }

        XCTAssertEqual(timeoutFinalizer.events.count, 1)
        XCTAssertEqual(timeoutFinalizer.events.first?.outcome, .failed)
        XCTAssertEqual(timeoutFinalizer.events.first?.remoteMutation, true)
    }

    func testQueuedUploadCancellationFinalizesOnceWithoutRemoteMutation() async throws {
        let coordinator = FakeTransferCoordinator()
        let finalizer = TransferFinalizerDouble()
        let queue = DispatchQueue(label: "FileTransferManagerTests.upload.suspended")
        queue.suspend()
        let manager = FileTransferManager(
            coordinator: coordinator,
            completionFinalizer: finalizer,
            transferQueue: queue
        )
        let device = try makeTransferDevice()
        let source = temporaryURL("queued-upload.bin")
        try Data([1]).write(to: source)
        let task = try manager.uploadFile(
            to: device,
            sourceURL: source,
            parentId: MTPObjectID.root.rawValue,
            storageId: device.storageInfo[0].storageID.rawValue
        )

        manager.cancelTask(task)
        manager.cancelTask(task)
        await waitUntil { task.status == .cancelled }

        XCTAssertEqual(finalizer.events.count, 1)
        XCTAssertEqual(finalizer.events.first?.outcome, .cancelled)
        XCTAssertEqual(finalizer.events.first?.remoteMutation, false)
        queue.resume()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(coordinator.uploadCalls.isEmpty)
    }

    func testManagerSourceContainsNoDirectKalamTransferSymbolsOrSleep() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot
            .appendingPathComponent("SwiftMTP/Services/MTP/FileTransferManager.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertFalse(source.contains("Kalam_Scan"))
        XCTAssertFalse(source.contains("Kalam_DownloadFile"))
        XCTAssertFalse(source.contains("Kalam_UploadFile"))
        XCTAssertFalse(source.contains("Kalam_CancelTask"))
        XCTAssertFalse(source.contains("Kalam_RefreshStorage"))
        XCTAssertFalse(source.contains("Kalam_ResetDeviceCache"))
        XCTAssertFalse(source.contains("Thread.sleep"))
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        condition: @escaping @MainActor () -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition(), clock.now < deadline {
            await Task.yield()
        }
        XCTAssertTrue(condition())
    }

    private func temporaryURL(_ name: String) -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory.appendingPathComponent(name)
    }
}

private final class TransferFinalizerDouble:
    MTPTransferCompletionFinalizing,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var storedEvents: [TransferCompletionEvent] = []

    var events: [TransferCompletionEvent] {
        lock.withLock { storedEvents }
    }

    func finalize(_ event: TransferCompletionEvent, for device: Device) {
        lock.withLock { storedEvents.append(event) }
    }
}

private final class FakeTransferCoordinator: MTPTransferCoordinating, @unchecked Sendable {
    struct DownloadCall {
        let appDeviceID: UUID
        let deviceID: MTPDeviceID
        let request: MTPDownloadRequest
        let cancellation: MTPCancellationToken
    }

    struct UploadCall {
        let appDeviceID: UUID
        let deviceID: MTPDeviceID
        let request: MTPUploadRequest
        let cancellation: MTPCancellationToken
    }

    var downloadHandler: (
        UUID,
        MTPDeviceID,
        MTPDownloadRequest,
        @escaping MTPTransferProgress,
        MTPCancellationToken
    ) throws -> Void = { _, _, _, _, _ in }
    var uploadHandler: (
        UUID,
        MTPDeviceID,
        MTPUploadRequest,
        @escaping MTPTransferProgress,
        MTPCancellationToken
    ) throws -> Void = { _, _, _, _, _ in }

    private let lock = NSLock()
    private var storedDownloadCalls: [DownloadCall] = []
    private var storedUploadCalls: [UploadCall] = []

    var downloadCalls: [DownloadCall] {
        lock.withLock { storedDownloadCalls }
    }

    var uploadCalls: [UploadCall] {
        lock.withLock { storedUploadCalls }
    }

    func download(
        appDeviceID: UUID,
        deviceID: MTPDeviceID,
        request: MTPDownloadRequest,
        progress: @escaping MTPTransferProgress,
        cancellation: MTPCancellationToken
    ) throws {
        lock.withLock {
            storedDownloadCalls.append(
                DownloadCall(
                    appDeviceID: appDeviceID,
                    deviceID: deviceID,
                    request: request,
                    cancellation: cancellation
                )
            )
        }
        try downloadHandler(appDeviceID, deviceID, request, progress, cancellation)
    }

    func upload(
        appDeviceID: UUID,
        deviceID: MTPDeviceID,
        request: MTPUploadRequest,
        progress: @escaping MTPTransferProgress,
        cancellation: MTPCancellationToken
    ) throws {
        lock.withLock {
            storedUploadCalls.append(
                UploadCall(
                    appDeviceID: appDeviceID,
                    deviceID: deviceID,
                    request: request,
                    cancellation: cancellation
                )
            )
        }
        try uploadHandler(appDeviceID, deviceID, request, progress, cancellation)
    }
}

@MainActor
private func makeTransferDevice() throws -> Device {
    let storageID = try MTPStorageID(validating: 1)
    return Device(
        deviceIndex: 0,
        mtpIdentity: MTPDeviceIdentity(
            providerKind: .go,
            deviceID: try MTPDeviceID(validating: "go:7")
        ),
        name: "Test",
        manufacturer: "Test",
        model: "Test",
        serialNumber: "",
        batteryLevel: nil,
        storageInfo: [
            StorageInfo(
                storageID: storageID,
                maxCapacity: 100,
                freeSpace: 100,
                description: "Test"
            ),
        ]
    )
}

private func makeTransferFile(
    size: UInt64 = 4,
    isDirectory: Bool = false
) throws -> FileItem {
    FileItem(
        objectID: try MTPObjectID(validating: 9),
        parentID: .root,
        storageID: try MTPStorageID(validating: 1),
        name: isDirectory ? "Folder" : "file.bin",
        path: isDirectory ? "Folder" : "file.bin",
        size: size,
        modifiedDate: nil,
        isDirectory: isDirectory
    )
}
