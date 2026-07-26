import XCTest
@testable import SwiftMTP

final class MTPConnectionCoordinatorTests: XCTestCase {
    func testSwitchingDevicesClosesPreviousAndRoutesOnlyExactStableID() throws {
        let go = FakeMTPBackend(providerKind: .go)
        let swift = FakeMTPBackend(providerKind: .swift)
        let coordinator = MTPConnectionCoordinator(
            factories: [
                .go: { go },
                .swift: { swift },
            ]
        )
        let firstAppID = UUID()
        let secondAppID = UUID()
        let firstID = try MTPDeviceID(validating: "go:1")
        let secondID = try MTPDeviceID(validating: "swift:1:2:18d1:4ee7")
        let storageID = try MTPStorageID(validating: 1)
        try coordinator.register(
            appDeviceID: firstAppID,
            snapshot: snapshot(firstID),
            providerKind: .go
        )
        try coordinator.register(
            appDeviceID: secondAppID,
            snapshot: snapshot(secondID),
            providerKind: .swift
        )

        try coordinator.selectDevice(firstAppID)
        XCTAssertEqual(go.openedDeviceIDs, [firstID])

        try coordinator.selectDevice(secondAppID)
        XCTAssertEqual(go.sessions.first?.closeCount, 1)
        XCTAssertEqual(go.shutdownCount, 1)
        XCTAssertEqual(swift.openedDeviceIDs, [secondID])
        XCTAssertThrowsError(
            try coordinator.refreshStorage(
                appDeviceID: secondAppID,
                deviceID: firstID,
                storageID: storageID
            )
        ) {
            XCTAssertEqual($0 as? MTPCoreError, .disconnected)
        }
        XCTAssertNoThrow(
            try coordinator.refreshStorage(
                appDeviceID: secondAppID,
                deviceID: secondID,
                storageID: storageID
            )
        )

        coordinator.close()
        XCTAssertEqual(swift.sessions.first?.closeCount, 1)
        XCTAssertEqual(swift.shutdownCount, 1)
    }

    func testActiveRegistrationCannotChangeProviderOrTransportIdentity() throws {
        let go = FakeMTPBackend(providerKind: .go)
        let coordinator = MTPConnectionCoordinator(factories: [.go: { go }])
        let appID = UUID()
        let firstID = try MTPDeviceID(validating: "go:1")
        let replacementID = try MTPDeviceID(validating: "go:2")
        try coordinator.register(
            appDeviceID: appID,
            snapshot: snapshot(firstID),
            providerKind: .go
        )
        try coordinator.selectDevice(appID)

        XCTAssertThrowsError(
            try coordinator.register(
                appDeviceID: appID,
                snapshot: snapshot(replacementID),
                providerKind: .swift
            )
        ) {
            XCTAssertEqual($0 as? MTPCoreError, .busy)
        }
        XCTAssertEqual(go.openedDeviceIDs, [firstID])
        coordinator.close()
    }

    private func snapshot(_ deviceID: MTPDeviceID) -> MTPDeviceSnapshot {
        MTPDeviceSnapshot(
            deviceID: deviceID,
            name: "Phone",
            manufacturer: "Acme",
            model: "Phone",
            storages: []
        )
    }
}
