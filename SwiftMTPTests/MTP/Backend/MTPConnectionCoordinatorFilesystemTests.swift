import XCTest
@testable import SwiftMTP

final class MTPConnectionCoordinatorFilesystemTests: XCTestCase {
    func testFilesystemOperationsRequireMatchingActiveAppAndTransportIdentity() throws {
        let backend = FakeMTPBackend(providerKind: .go)
        let coordinator = MTPConnectionCoordinator(factories: [.go: { backend }])
        let appID = UUID()
        let otherAppID = UUID()
        let deviceID = try MTPDeviceID(validating: "go:7")
        let otherDeviceID = try MTPDeviceID(validating: "go:8")
        let storageID = try MTPStorageID(validating: 1)
        let snapshot = MTPDeviceSnapshot(
            deviceID: deviceID,
            name: "Phone",
            manufacturer: "Acme",
            model: "P",
            storages: []
        )
        try coordinator.register(appDeviceID: appID, snapshot: snapshot, providerKind: .go)
        try coordinator.selectDevice(appID)

        XCTAssertEqual(
            try coordinator.listObjects(
                appDeviceID: appID,
                deviceID: deviceID,
                storageID: storageID,
                parentID: .root
            ),
            MTPDirectoryListing(objects: [], failures: [])
        )
        XCTAssertThrowsError(
            try coordinator.listObjects(
                appDeviceID: otherAppID,
                deviceID: deviceID,
                storageID: storageID,
                parentID: .root
            )
        )
        XCTAssertThrowsError(
            try coordinator.createFolder(
                appDeviceID: appID,
                deviceID: otherDeviceID,
                storageID: storageID,
                parentID: .root,
                name: "new"
            )
        )
        coordinator.close()
    }

    func testTerminalFilesystemFailureInvalidatesActiveConnectionExactlyOnce() throws {
        let backend = FakeMTPBackend(providerKind: .go)
        let coordinator = MTPConnectionCoordinator(factories: [.go: { backend }])
        let appID = UUID()
        let deviceID = try MTPDeviceID(validating: "go:7")
        let storageID = try MTPStorageID(validating: 1)
        let snapshot = MTPDeviceSnapshot(
            deviceID: deviceID,
            name: "Phone",
            manufacturer: "Acme",
            model: "P",
            storages: []
        )
        try coordinator.register(appDeviceID: appID, snapshot: snapshot, providerKind: .go)
        try coordinator.selectDevice(appID)
        let session = try XCTUnwrap(backend.sessions.first)
        session.listObjectsHandler = { _, _ in throw MTPCoreError.timeout }

        XCTAssertThrowsError(
            try coordinator.listObjects(
                appDeviceID: appID,
                deviceID: deviceID,
                storageID: storageID,
                parentID: .root
            )
        ) {
            XCTAssertEqual($0 as? MTPCoreError, .timeout)
        }
        XCTAssertEqual(session.closeCount, 1)
        XCTAssertEqual(backend.shutdownCount, 1)

        XCTAssertThrowsError(
            try coordinator.listObjects(
                appDeviceID: appID,
                deviceID: deviceID,
                storageID: storageID,
                parentID: .root
            )
        ) {
            XCTAssertEqual($0 as? MTPCoreError, .disconnected)
        }
        coordinator.close()
        XCTAssertEqual(session.closeCount, 1)
        XCTAssertEqual(backend.shutdownCount, 1)
    }

    func testRecoverableFilesystemResponseKeepsActiveConnection() throws {
        let backend = FakeMTPBackend(providerKind: .go)
        let coordinator = MTPConnectionCoordinator(factories: [.go: { backend }])
        let appID = UUID()
        let deviceID = try MTPDeviceID(validating: "go:7")
        let storageID = try MTPStorageID(validating: 1)
        let snapshot = MTPDeviceSnapshot(
            deviceID: deviceID,
            name: "Phone",
            manufacturer: "Acme",
            model: "P",
            storages: []
        )
        try coordinator.register(appDeviceID: appID, snapshot: snapshot, providerKind: .go)
        try coordinator.selectDevice(appID)
        let session = try XCTUnwrap(backend.sessions.first)
        session.listObjectsHandler = { _, _ in
            throw MTPCoreError.response(code: .invalidObjectHandle)
        }

        XCTAssertThrowsError(
            try coordinator.listObjects(
                appDeviceID: appID,
                deviceID: deviceID,
                storageID: storageID,
                parentID: .root
            )
        )
        XCTAssertEqual(session.closeCount, 0)
        XCTAssertEqual(backend.shutdownCount, 0)

        session.listObjectsHandler = nil
        XCTAssertNoThrow(
            try coordinator.listObjects(
                appDeviceID: appID,
                deviceID: deviceID,
                storageID: storageID,
                parentID: .root
            )
        )
        coordinator.close()
        XCTAssertEqual(session.closeCount, 1)
        XCTAssertEqual(backend.shutdownCount, 1)
    }
}
