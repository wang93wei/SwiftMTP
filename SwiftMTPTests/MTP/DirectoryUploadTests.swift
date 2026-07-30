import Darwin
import Foundation
import XCTest
@testable import SwiftMTP

final class MTPDirectoryUploadManifestTests: XCTestCase {
    func testManifestContainsOnlyVisibleRegularFilesInStableRelativeOrder() throws {
        let root = try makeTemporaryDirectory()
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("nested"),
            withIntermediateDirectories: true
        )
        try Data([1, 2]).write(to: root.appendingPathComponent("nested/b.bin"))
        try Data([3]).write(to: root.appendingPathComponent("a.txt"))
        try Data([4]).write(to: root.appendingPathComponent(".hidden"))
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Empty"),
            withIntermediateDirectories: true
        )
        let package = root.appendingPathComponent("Ignored.app")
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try Data([5]).write(to: package.appendingPathComponent("inside.bin"))

        let manifest = try MTPDirectoryUploadManifest.build(from: root)

        XCTAssertEqual(manifest.entries.map(\.relativePath), ["a.txt", "nested/b.bin"])
        XCTAssertEqual(manifest.entries.map(\.size), [1, 2])
        XCTAssertEqual(manifest.totalSize, 3)
        XCTAssertEqual(manifest.requiredFolderPaths, ["nested"])
    }

    func testEmptyDirectoryProducesEmptyManifestWithoutCopyingEmptyFolders() throws {
        let root = try makeTemporaryDirectory()
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("nested/empty"),
            withIntermediateDirectories: true
        )

        let manifest = try MTPDirectoryUploadManifest.build(from: root)

        XCTAssertTrue(manifest.entries.isEmpty)
        XCTAssertTrue(manifest.requiredFolderPaths.isEmpty)
        XCTAssertEqual(manifest.totalSize, 0)
    }

    func testManifestRejectsSymbolicLinkAndUnsafeRoot() throws {
        let root = try makeTemporaryDirectory()
        let target = root.appendingPathComponent("target.bin")
        try Data([1]).write(to: target)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("link.bin"),
            withDestinationURL: target
        )

        let manifest = try MTPDirectoryUploadManifest.build(from: root)
        XCTAssertEqual(manifest.entries.map(\.relativePath), ["target.bin"])

        XCTAssertThrowsError(
            try MTPDirectoryUploadManifest.build(
                from: root.appendingPathComponent("../missing").standardizedFileURL
            )
        ) {
            XCTAssertTrue($0 is MTPCoreError)
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

@MainActor
final class FileTransferManagerDirectoryUploadTests: XCTestCase {
    func testSubmissionReturnsParentTaskAndAllFilesComplete() async throws {
        let coordinator = DirectoryTransferCoordinatorDouble()
        let manager = FileTransferManager(coordinator: coordinator)
        let device = try makeDirectoryTransferDevice()
        let root = try makeDirectoryFixture([
            "a.txt": 1,
            "nested/b.txt": 2,
            "nested/c.txt": 3,
        ])

        let task = try manager.uploadDirectory(
            to: device,
            sourceURL: root,
            parentId: MTPObjectID.root.rawValue,
            storageId: device.storageInfo[0].storageID.rawValue
        )

        await waitUntil { task.directoryUploadResult != nil }

        let result = try XCTUnwrap(task.directoryUploadResult)
        XCTAssertEqual(result.outcome, .succeeded)
        XCTAssertEqual(result.uploadedFiles, 3)
        XCTAssertEqual(result.failedFiles, 0)
        XCTAssertEqual(task.status, .completed)
        XCTAssertEqual(coordinator.uploadCalls.map(\.request.name), ["a.txt", "b.txt", "c.txt"])
        XCTAssertEqual(Set(coordinator.createCalls.map(\.name)), Set([root.lastPathComponent, "nested"]))
        XCTAssertEqual(coordinator.createCalls.filter { $0.name == "nested" }.count, 1)
        XCTAssertEqual(Set(coordinator.uploadCalls.map(\.cancellationID)).count, 1)
        XCTAssertEqual(manager.completedTasks.filter { $0.id == task.id }.count, 1)
    }

    func testExistingRootFolderIsReusedWithoutCreatingDuplicate() async throws {
        let coordinator = DirectoryTransferCoordinatorDouble()
        coordinator.existingFolders["Upload"] = try MTPObjectID(validating: 77)
        let manager = FileTransferManager(coordinator: coordinator)
        let task = try manager.uploadDirectory(
            to: try makeDirectoryTransferDevice(),
            sourceURL: try makeDirectoryFixture(["a.txt": 1]),
            parentId: MTPObjectID.root.rawValue,
            storageId: 1
        )

        await waitUntil { task.directoryUploadResult != nil }

        XCTAssertEqual(task.directoryUploadResult?.outcome, .succeeded)
        XCTAssertTrue(coordinator.createCalls.isEmpty)
        XCTAssertEqual(coordinator.uploadCalls.first?.request.parentID.rawValue, 77)
    }

    func testCompletionHandlerRunsExactlyOnceWithFinalTaskResult() async throws {
        let coordinator = DirectoryTransferCoordinatorDouble()
        let manager = FileTransferManager(coordinator: coordinator)
        var completions: [MTPDirectoryUploadResult] = []
        let task = try manager.uploadDirectory(
            to: try makeDirectoryTransferDevice(),
            sourceURL: try makeDirectoryFixture(["a.txt": 1]),
            parentId: MTPObjectID.root.rawValue,
            storageId: 1,
            completionHandler: { completions.append($0) }
        )

        await waitUntil { task.directoryUploadResult != nil }
        manager.cancelTask(task)
        await Task.yield()

        XCTAssertEqual(completions, [task.directoryUploadResult].compactMap { $0 })
        XCTAssertEqual(manager.completedTasks.filter { $0.id == task.id }.count, 1)
    }

    func testEmptyRootCompletesWithoutRemoteMutation() async throws {
        let coordinator = DirectoryTransferCoordinatorDouble()
        let manager = FileTransferManager(coordinator: coordinator)
        let task = try manager.uploadDirectory(
            to: try makeDirectoryTransferDevice(),
            sourceURL: try makeDirectoryFixture([:]),
            parentId: MTPObjectID.root.rawValue,
            storageId: 1
        )

        await waitUntil { task.directoryUploadResult != nil }

        XCTAssertEqual(task.directoryUploadResult?.outcome, .succeeded)
        XCTAssertEqual(task.directoryUploadResult?.totalFiles, 0)
        XCTAssertEqual(task.status, .completed)
        XCTAssertTrue(coordinator.createCalls.isEmpty)
        XCTAssertTrue(coordinator.uploadCalls.isEmpty)
    }

    func testAllFailedAndPartialHaveDistinctTypedTerminalOutcomes() async throws {
        let device = try makeDirectoryTransferDevice()

        let allFailedCoordinator = DirectoryTransferCoordinatorDouble()
        allFailedCoordinator.failedUploadNames = ["a.txt", "b.txt"]
        let allFailedManager = FileTransferManager(coordinator: allFailedCoordinator)
        let allFailedTask = try allFailedManager.uploadDirectory(
            to: device,
            sourceURL: try makeDirectoryFixture(["a.txt": 1, "b.txt": 1]),
            parentId: MTPObjectID.root.rawValue,
            storageId: 1
        )
        await waitUntil { allFailedTask.directoryUploadResult != nil }
        XCTAssertEqual(allFailedTask.directoryUploadResult?.outcome, .failed)
        if case .failed = allFailedTask.status {} else {
            XCTFail("all-failed directory must be failed")
        }

        let partialCoordinator = DirectoryTransferCoordinatorDouble()
        partialCoordinator.failedUploadNames = ["b.txt"]
        let partialManager = FileTransferManager(coordinator: partialCoordinator)
        let partialTask = try partialManager.uploadDirectory(
            to: device,
            sourceURL: try makeDirectoryFixture(["a.txt": 1, "b.txt": 1]),
            parentId: MTPObjectID.root.rawValue,
            storageId: 1
        )
        await waitUntil { partialTask.directoryUploadResult != nil }
        XCTAssertEqual(partialTask.directoryUploadResult?.outcome, .partial)
        if case .partial = partialTask.status {} else {
            XCTFail("partial directory must not be completed")
        }
    }

    func testCreateRootFailureProducesAllFailedSummaryWithoutUploads() async throws {
        let coordinator = DirectoryTransferCoordinatorDouble()
        coordinator.failedFolderNames = ["Root"]
        let manager = FileTransferManager(coordinator: coordinator)
        let task = try manager.uploadDirectory(
            to: try makeDirectoryTransferDevice(),
            sourceURL: try makeDirectoryFixture(["a.txt": 1], named: "Root"),
            parentId: MTPObjectID.root.rawValue,
            storageId: 1
        )

        await waitUntil { task.directoryUploadResult != nil }

        XCTAssertEqual(task.directoryUploadResult?.outcome, .failed)
        XCTAssertEqual(task.directoryUploadResult?.failedFiles, 1)
        XCTAssertTrue(coordinator.uploadCalls.isEmpty)
    }

    func testQueuedCancellationDoesNotMutateRemoteOrAffectSecondOperation() async throws {
        let coordinator = DirectoryTransferCoordinatorDouble()
        let queue = DispatchQueue(label: "DirectoryUploadTests.suspended")
        queue.suspend()
        let manager = FileTransferManager(coordinator: coordinator, transferQueue: queue)
        let device = try makeDirectoryTransferDevice()
        let cancelled = try manager.uploadDirectory(
            to: device,
            sourceURL: try makeDirectoryFixture(["cancelled.txt": 1]),
            parentId: MTPObjectID.root.rawValue,
            storageId: 1
        )
        let surviving = try manager.uploadDirectory(
            to: device,
            sourceURL: try makeDirectoryFixture(["surviving.txt": 1]),
            parentId: MTPObjectID.root.rawValue,
            storageId: 1
        )

        manager.cancelTask(cancelled)
        queue.resume()
        await waitUntil { surviving.directoryUploadResult != nil }

        XCTAssertEqual(cancelled.status, .cancelled)
        XCTAssertEqual(surviving.directoryUploadResult?.outcome, .succeeded)
        XCTAssertEqual(coordinator.uploadCalls.map(\.request.name), ["surviving.txt"])
    }

    func testMidOperationCancellationStopsRemainingFiles() async throws {
        let coordinator = DirectoryTransferCoordinatorDouble()
        let firstUpload = expectation(description: "first upload")
        coordinator.onUpload = { call in
            if call.request.name == "a.txt" {
                firstUpload.fulfill()
                while !call.cancellation.isCancelled {
                    sched_yield()
                }
                throw MTPCoreError.cancelled
            }
        }
        let manager = FileTransferManager(coordinator: coordinator)
        let task = try manager.uploadDirectory(
            to: try makeDirectoryTransferDevice(),
            sourceURL: try makeDirectoryFixture(["a.txt": 1, "b.txt": 1]),
            parentId: MTPObjectID.root.rawValue,
            storageId: 1
        )
        await fulfillment(of: [firstUpload], timeout: 2)

        manager.cancelTask(task)
        await waitUntil { task.status == .cancelled }

        XCTAssertEqual(coordinator.uploadCalls.map(\.request.name), ["a.txt"])
        XCTAssertEqual(manager.completedTasks.filter { $0.id == task.id }.count, 1)
    }

    func testPreflightInsufficientStorageFailsTaskWithoutRemoteMutation() async throws {
        let coordinator = DirectoryTransferCoordinatorDouble()
        let manager = FileTransferManager(coordinator: coordinator)
        let device = try makeDirectoryTransferDevice(freeSpace: 1)

        let task = try manager.uploadDirectory(
            to: device,
            sourceURL: try makeDirectoryFixture(["large.bin": 2]),
            parentId: MTPObjectID.root.rawValue,
            storageId: 1
        )
        await waitUntil {
            if case .failed = task.status { return true }
            return false
        }
        XCTAssertEqual(task.directoryUploadResult?.outcome, .failed)
        XCTAssertEqual(task.directoryUploadResult?.failedFiles, 1)
        XCTAssertTrue(manager.activeTasks.isEmpty)
        XCTAssertTrue(coordinator.createCalls.isEmpty)
        XCTAssertTrue(coordinator.uploadCalls.isEmpty)
    }

    func testDirectorySourceContainsNoDirectKalamSymbols() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "SwiftMTP/Services/MTP/FileTransferManager+DirectoryUpload.swift"
            ),
            encoding: .utf8
        )

        XCTAssertFalse(source.contains("Kalam_"))
        XCTAssertFalse(source.contains("Task.sleep"))
        XCTAssertFalse(source.contains("directoryUploadCancelled"))
    }

}

private final class DirectoryTransferCoordinatorDouble:
    MTPTransferCoordinating,
    @unchecked Sendable
{
    struct FolderCall {
        let name: String
        let cancellationID: ObjectIdentifier
    }

    struct UploadCall {
        let request: MTPUploadRequest
        let cancellation: MTPCancellationToken
        let cancellationID: ObjectIdentifier
    }

    private let lock = NSLock()
    private var nextObjectID: UInt32 = 100
    private var storedCreateCalls: [FolderCall] = []
    private var storedUploadCalls: [UploadCall] = []
    var failedFolderNames: Set<String> = []
    var failedUploadNames: Set<String> = []
    var existingFolders: [String: MTPObjectID] = [:]
    var onUpload: ((UploadCall) throws -> Void)?

    var createCalls: [FolderCall] { lock.withLock { storedCreateCalls } }
    var uploadCalls: [UploadCall] { lock.withLock { storedUploadCalls } }

    func listObjects(
        appDeviceID: UUID,
        deviceID: MTPDeviceID,
        storageID: MTPStorageID,
        parentID: MTPObjectID,
        cancellation: MTPCancellationToken
    ) throws -> MTPDirectoryListing {
        try cancellation.throwIfCancelled()
        return MTPDirectoryListing(
            objects: existingFolders.map { name, objectID in
                MTPObject(
                    id: objectID,
                    parentID: parentID,
                    storageID: storageID,
                    name: name,
                    size: 0,
                    isFolder: true,
                    modificationDate: nil
                )
            },
            failures: []
        )
    }

    func createFolder(
        appDeviceID: UUID,
        deviceID: MTPDeviceID,
        storageID: MTPStorageID,
        parentID: MTPObjectID,
        name: String,
        cancellation: MTPCancellationToken
    ) throws -> MTPObjectID {
        try cancellation.throwIfCancelled()
        if failedFolderNames.contains(name) {
            throw MTPCoreError.response(code: .generalError)
        }
        return try lock.withLock {
            nextObjectID += 1
            storedCreateCalls.append(
                FolderCall(name: name, cancellationID: ObjectIdentifier(cancellation))
            )
            return try MTPObjectID(validating: nextObjectID)
        }
    }

    func download(
        appDeviceID: UUID,
        deviceID: MTPDeviceID,
        request: MTPDownloadRequest,
        progress: @escaping MTPTransferProgress,
        cancellation: MTPCancellationToken
    ) throws {}

    func upload(
        appDeviceID: UUID,
        deviceID: MTPDeviceID,
        request: MTPUploadRequest,
        progress: @escaping MTPTransferProgress,
        cancellation: MTPCancellationToken
    ) throws {
        let call = UploadCall(
            request: request,
            cancellation: cancellation,
            cancellationID: ObjectIdentifier(cancellation)
        )
        lock.withLock { storedUploadCalls.append(call) }
        if failedUploadNames.contains(request.name) {
            throw MTPCoreError.response(code: .generalError)
        }
        try onUpload?(call)
        try cancellation.throwIfCancelled()
        progress(request.size)
    }
}

@MainActor
private func makeDirectoryTransferDevice(freeSpace: UInt64 = 100) throws -> Device {
    Device(
        deviceIndex: 0,
        mtpIdentity: MTPDeviceIdentity(
            providerKind: .go,
            deviceID: try MTPDeviceID(validating: "go:directory-tests")
        ),
        name: "Directory Test",
        manufacturer: "Test",
        model: "Test",
        serialNumber: "",
        batteryLevel: nil,
        storageInfo: [
            StorageInfo(
                storageID: try MTPStorageID(validating: 1),
                maxCapacity: 100,
                freeSpace: freeSpace,
                description: "Test"
            ),
        ]
    )
}

private func makeDirectoryFixture(
    _ files: [String: Int],
    named name: String = "Upload"
) throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        .appendingPathComponent(name, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    for (relativePath, size) in files {
        let file = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(repeating: 1, count: size).write(to: file)
    }
    return root
}
