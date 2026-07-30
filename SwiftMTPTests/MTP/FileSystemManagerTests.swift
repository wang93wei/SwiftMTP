import XCTest
@testable import SwiftMTP

@MainActor
final class FileSystemManagerTests: XCTestCase {
    func testSuccessfulListingMapsFieldsCachesAndExpiresWithInjectedClock() async throws {
        let coordinator = FakeFileSystemCoordinator()
        let clock = TestClock(Date(timeIntervalSince1970: 100))
        let device = try makeDevice()
        coordinator.listing = MTPDirectoryListing(
            objects: [
                MTPObject(
                    id: try MTPObjectID(validating: 2),
                    parentID: .root,
                    storageID: try MTPStorageID(validating: 1),
                    name: "readme.txt",
                    size: 42,
                    isFolder: false,
                    modificationDate: Date(timeIntervalSince1970: 10)
                ),
            ],
            failures: []
        )
        let manager = FileSystemManager(
            coordinator: coordinator,
            cacheTTL: 60,
            now: { clock.value }
        )

        let first = try await manager.getRootFiles(for: device)
        let cached = try await manager.getRootFiles(for: device)
        clock.value = Date(timeIntervalSince1970: 161)
        _ = try await manager.getRootFiles(for: device)

        XCTAssertEqual(first.first?.objectID, try MTPObjectID(validating: 2))
        XCTAssertEqual(first.first?.parentID, .root)
        XCTAssertEqual(first.first?.storageID, try MTPStorageID(validating: 1))
        XCTAssertEqual(first.first?.fileType, "TXT")
        XCTAssertEqual(first.first?.size, 42)
        XCTAssertEqual(cached, first)
        XCTAssertEqual(coordinator.listCount, 2)
    }

    func testTerminalListingFailureIsThrownAndNeverCached() async throws {
        let coordinator = FakeFileSystemCoordinator()
        coordinator.listError = .timeout
        let device = try makeDevice()
        let manager = FileSystemManager(coordinator: coordinator)

        await XCTAssertThrowsErrorAsync {
            _ = try await manager.getRootFiles(for: device)
        }
        coordinator.listError = nil
        let items = try await manager.getRootFiles(for: device)
        XCTAssertEqual(items, [])
        XCTAssertEqual(coordinator.listCount, 2)
    }

    func testCreateAndDeleteInvalidateOnlyAfterConfirmedSuccess() async throws {
        let coordinator = FakeFileSystemCoordinator()
        let device = try makeDevice()
        let manager = FileSystemManager(coordinator: coordinator)
        _ = try await manager.getRootFiles(for: device)
        XCTAssertEqual(coordinator.listCount, 1)

        coordinator.createError = .timeout
        await XCTAssertThrowsErrorAsync {
            _ = try await manager.createFolder(
                for: device,
                parent: nil,
                name: "new"
            )
        }
        _ = try await manager.getRootFiles(for: device)
        XCTAssertEqual(coordinator.listCount, 1)

        coordinator.createError = nil
        let folderID = try await manager.createFolder(
            for: device,
            parent: nil,
            name: "new"
        )
        _ = try await manager.getRootFiles(for: device)
        XCTAssertEqual(folderID, try MTPObjectID(validating: 9))
        XCTAssertEqual(coordinator.lastCreateStorageID, try MTPStorageID(validating: 1))
        XCTAssertEqual(coordinator.lastCreateParentID, .root)
        XCTAssertEqual(coordinator.listCount, 2)
    }

    func testBatchDeleteInvalidatesOnceWhenAnyObjectSucceeds() async throws {
        let coordinator = FakeFileSystemCoordinator()
        let failedID = try MTPObjectID(validating: 3)
        coordinator.deleteErrors[failedID] = .response(code: .generalError)
        let device = try makeDevice()
        let manager = FileSystemManager(coordinator: coordinator)
        _ = try await manager.getRootFiles(for: device)

        let result = try await manager.deleteObjects(
            for: device,
            objectIDs: [
                try MTPObjectID(validating: 2),
                failedID,
            ]
        )
        _ = try await manager.getRootFiles(for: device)

        XCTAssertEqual(result.succeededObjectIDs, [try MTPObjectID(validating: 2)])
        XCTAssertEqual(
            result.failures,
            [
                FileSystemDeleteFailure(
                    objectID: failedID,
                    error: .response(code: .generalError)
                ),
            ]
        )
        XCTAssertEqual(coordinator.deleteCount, 2)
        XCTAssertEqual(coordinator.listCount, 2)
    }

    func testOperationWideBatchDeleteFailureThrowsInsteadOfBecomingPerObjectFailures() async throws {
        let coordinator = FakeFileSystemCoordinator()
        let firstID = try MTPObjectID(validating: 2)
        coordinator.deleteErrors[firstID] = .disconnected
        let manager = FileSystemManager(coordinator: coordinator)

        await XCTAssertThrowsErrorAsync(expected: MTPCoreError.disconnected) {
            _ = try await manager.deleteObjects(
                for: try makeDevice(),
                objectIDs: [firstID, try MTPObjectID(validating: 3)]
            )
        }
        XCTAssertEqual(coordinator.deleteCount, 1)
    }

    func testTerminalResponseBatchDeleteFailureThrowsInsteadOfContinuing() async throws {
        let coordinator = FakeFileSystemCoordinator()
        let firstID = try MTPObjectID(validating: 2)
        coordinator.deleteErrors[firstID] = .response(code: .sessionNotOpen)
        let manager = FileSystemManager(coordinator: coordinator)

        await XCTAssertThrowsErrorAsync(
            expected: MTPCoreError.response(code: .sessionNotOpen)
        ) {
            _ = try await manager.deleteObjects(
                for: try makeDevice(),
                objectIDs: [firstID, try MTPObjectID(validating: 3)]
            )
        }
        XCTAssertEqual(coordinator.deleteCount, 1)
    }

    func testScopedInvalidationPreventsLateListingWithoutEvictingOtherIdentity() async throws {
        let coordinator = BlockingFileSystemCoordinator()
        let appDeviceID = UUID()
        let firstDevice = try makeDevice(id: appDeviceID, deviceID: "go:7")
        let secondDevice = try makeDevice(id: appDeviceID, deviceID: "go:8")
        let manager = FileSystemManager(coordinator: coordinator)

        let firstRequest = Task {
            try await manager.getRootFiles(for: firstDevice)
        }
        await coordinator.waitForFirstRequest()
        _ = try await manager.getRootFiles(for: secondDevice)
        await manager.clearCache(for: firstDevice)
        await coordinator.resumeFirstRequest()
        _ = try await firstRequest.value
        _ = try await manager.getRootFiles(for: secondDevice)
        _ = try await manager.getRootFiles(for: firstDevice)

        let listCount = await coordinator.listCount
        XCTAssertEqual(listCount, 3)
    }

    func testCacheIsIdentityScopedAndRootWithoutStorageDoesNotCallBackend() async throws {
        let coordinator = FakeFileSystemCoordinator()
        let appDeviceID = UUID()
        let firstDevice = try makeDevice(id: appDeviceID, deviceID: "go:7")
        let secondDevice = try makeDevice(id: appDeviceID, deviceID: "go:8")
        let noStorageDevice = try makeDevice(deviceID: "go:9", includesStorage: false)
        let manager = FileSystemManager(coordinator: coordinator)

        _ = try await manager.getRootFiles(for: firstDevice)
        _ = try await manager.getRootFiles(for: firstDevice)
        _ = try await manager.getRootFiles(for: secondDevice)
        let noStorageItems = try await manager.getRootFiles(for: noStorageDevice)

        XCTAssertEqual(coordinator.listCount, 2)
        XCTAssertEqual(noStorageItems, [])
    }

    func testTypedChildDestinationComesFromParentItem() async throws {
        let coordinator = FakeFileSystemCoordinator()
        let manager = FileSystemManager(coordinator: coordinator)
        let parent = FileItem(
            objectID: try MTPObjectID(validating: 44),
            parentID: .root,
            storageID: try MTPStorageID(validating: 7),
            name: "Pictures",
            path: "Pictures",
            size: 0,
            modifiedDate: nil,
            isDirectory: true
        )

        _ = try await manager.createFolder(
            for: try makeDevice(),
            parent: parent,
            name: "Summer"
        )

        XCTAssertEqual(coordinator.lastCreateStorageID, parent.storageID)
        XCTAssertEqual(coordinator.lastCreateParentID, parent.objectID)
        XCTAssertNotEqual(
            coordinator.lastCreateStorageID?.rawValue,
            MTPObjectID.root.rawValue
        )
    }

    func testRootCreateWithoutStorageThrowsBeforeCoordinatorCall() async throws {
        let coordinator = FakeFileSystemCoordinator()
        let manager = FileSystemManager(coordinator: coordinator)

        await XCTAssertThrowsErrorAsync(
            expected: .invalidInput("device has no writable storage")
        ) {
            _ = try await manager.createFolder(
                for: try makeDevice(includesStorage: false),
                parent: nil,
                name: "No Destination"
            )
        }

        XCTAssertNil(coordinator.lastCreateStorageID)
        XCTAssertNil(coordinator.lastCreateParentID)
    }
}

private final class FakeFileSystemCoordinator:
    MTPFileSystemCoordinating,
    @unchecked Sendable
{
    private let lock = NSLock()
    var listing = MTPDirectoryListing(objects: [], failures: [])
    var listError: MTPCoreError?
    var createError: MTPCoreError?
    var deleteErrors: [MTPObjectID: MTPCoreError] = [:]
    private(set) var listCount = 0
    private(set) var deleteCount = 0
    private(set) var lastCreateStorageID: MTPStorageID?
    private(set) var lastCreateParentID: MTPObjectID?

    func listObjects(
        appDeviceID: UUID,
        deviceID: MTPDeviceID,
        storageID: MTPStorageID,
        parentID: MTPObjectID
    ) async throws -> MTPDirectoryListing {
        try lock.withLock {
            listCount += 1
            if let listError {
                throw listError
            }
            return listing
        }
    }

    func createFolder(
        appDeviceID: UUID,
        deviceID: MTPDeviceID,
        storageID: MTPStorageID,
        parentID: MTPObjectID,
        name: String
    ) async throws -> MTPObjectID {
        try lock.withLock {
            if let createError {
                throw createError
            }
            lastCreateStorageID = storageID
            lastCreateParentID = parentID
            return try MTPObjectID(validating: 9)
        }
    }

    func deleteObject(
        appDeviceID: UUID,
        deviceID: MTPDeviceID,
        objectID: MTPObjectID
    ) async throws {
        try lock.withLock {
            deleteCount += 1
            if let error = deleteErrors[objectID] {
                throw error
            }
        }
    }

    func refreshStorage(
        appDeviceID: UUID,
        deviceID: MTPDeviceID,
        storageID: MTPStorageID
    ) async throws -> MTPStorage {
        MTPStorage(id: storageID, description: "Internal", freeSpace: 1, maxCapacity: 2)
    }
}

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Date

    init(_ value: Date) {
        stored = value
    }

    var value: Date {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

private actor BlockingFileSystemCoordinator: MTPFileSystemCoordinating {
    private(set) var listCount = 0
    private var firstRequestContinuation: CheckedContinuation<MTPDirectoryListing, Never>?

    func listObjects(
        appDeviceID: UUID,
        deviceID: MTPDeviceID,
        storageID: MTPStorageID,
        parentID: MTPObjectID
    ) async throws -> MTPDirectoryListing {
        listCount += 1
        guard listCount == 1 else {
            return MTPDirectoryListing(objects: [], failures: [])
        }
        return await withCheckedContinuation { continuation in
            firstRequestContinuation = continuation
        }
    }

    func waitForFirstRequest() async {
        while firstRequestContinuation == nil {
            await Task.yield()
        }
    }

    func resumeFirstRequest() {
        firstRequestContinuation?.resume(
            returning: MTPDirectoryListing(objects: [], failures: [])
        )
        firstRequestContinuation = nil
    }

    func createFolder(
        appDeviceID: UUID,
        deviceID: MTPDeviceID,
        storageID: MTPStorageID,
        parentID: MTPObjectID,
        name: String
    ) async throws -> MTPObjectID {
        try MTPObjectID(validating: 9)
    }

    func deleteObject(
        appDeviceID: UUID,
        deviceID: MTPDeviceID,
        objectID: MTPObjectID
    ) async throws {}

    func refreshStorage(
        appDeviceID: UUID,
        deviceID: MTPDeviceID,
        storageID: MTPStorageID
    ) async throws -> MTPStorage {
        MTPStorage(id: storageID, description: "Internal", freeSpace: 1, maxCapacity: 2)
    }
}

@MainActor
private func makeDevice(
    id: UUID = UUID(),
    deviceID rawDeviceID: String = "go:7",
    includesStorage: Bool = true
) throws -> Device {
    let deviceID = try MTPDeviceID(validating: rawDeviceID)
    return Device(
        id: id,
        deviceIndex: 0,
        mtpIdentity: MTPDeviceIdentity(providerKind: .go, deviceID: deviceID),
        name: "Phone",
        manufacturer: "Acme",
        model: "P",
        serialNumber: "",
        batteryLevel: nil,
        storageInfo: includesStorage
            ? [
                StorageInfo(
                    storageID: try MTPStorageID(validating: 1),
                    maxCapacity: 2,
                    freeSpace: 1,
                    description: "Internal"
                ),
            ]
            : []
    )
}

@MainActor
private func XCTAssertThrowsErrorAsync(
    expected: MTPCoreError? = nil,
    _ expression: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected error", file: file, line: line)
    } catch {
        if let expected {
            XCTAssertEqual(error as? MTPCoreError, expected, file: file, line: line)
        }
    }
}
