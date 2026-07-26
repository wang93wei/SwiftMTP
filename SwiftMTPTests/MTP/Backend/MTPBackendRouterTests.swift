import XCTest
@testable import SwiftMTP

final class MTPBackendRouterTests: XCTestCase {
    func testProviderAndExactDeviceAreFixedUntilSessionCloses() throws {
        let go = FakeMTPBackend(providerKind: .go)
        let swift = FakeMTPBackend(providerKind: .swift)
        let router = MTPBackendRouter(
            initialProvider: .go,
            factories: [
                .go: { go },
                .swift: { swift },
            ]
        )
        let firstDevice = try MTPDeviceID(validating: "usb:001:002")
        let secondDevice = try MTPDeviceID(validating: "usb:001:003")

        let firstSession = try router.openSession(for: firstDevice)
        XCTAssertEqual(firstSession.providerKind, .go)
        XCTAssertEqual(firstSession.deviceID, firstDevice)
        XCTAssertEqual(go.openedDeviceIDs, [firstDevice])
        XCTAssertThrowsError(try router.selectProvider(.swift)) {
            XCTAssertEqual($0 as? MTPCoreError, .busy)
        }
        XCTAssertThrowsError(try router.openSession(for: secondDevice)) {
            XCTAssertEqual($0 as? MTPCoreError, .busy)
        }

        firstSession.close()
        try router.selectProvider(.swift)
        let secondSession = try router.openSession(for: secondDevice)
        XCTAssertEqual(secondSession.providerKind, .swift)
        XCTAssertEqual(swift.openedDeviceIDs, [secondDevice])
        secondSession.close()
    }

    func testClosedSessionRejectsDelegationAndCloseIsIdempotent() throws {
        let backend = FakeMTPBackend(providerKind: .go)
        let router = MTPBackendRouter(initialProvider: .go, factories: [.go: { backend }])
        let deviceID = try MTPDeviceID(validating: "usb:001:002")
        let storageID = try MTPStorageID(validating: 1)
        let session = try router.openSession(for: deviceID)

        session.close()
        session.close()

        XCTAssertEqual(backend.sessions.single?.closeCount, 1)
        XCTAssertThrowsError(try session.refreshStorage(storageID)) {
            XCTAssertEqual($0 as? MTPCoreError, .disconnected)
        }
        XCTAssertNoThrow(try router.openSession(for: deviceID).close())
    }

    func testDroppingSessionClosesUnderlyingAndReleasesRouter() throws {
        let backend = FakeMTPBackend(providerKind: .go)
        let router = MTPBackendRouter(initialProvider: .go, factories: [.go: { backend }])
        let deviceID = try MTPDeviceID(validating: "usb:001:002")
        var session: (any MTPBackendSession)? = try router.openSession(for: deviceID)

        weak var weakSession = session
        session = nil

        XCTAssertNil(weakSession)
        XCTAssertEqual(backend.sessions.single?.closeCount, 1)
        XCTAssertNoThrow(try router.openSession(for: deviceID).close())
    }

    func testRouterOwnsBackendLifecycleForEachSession() throws {
        let backend = FakeMTPBackend(providerKind: .go)
        let router = MTPBackendRouter(initialProvider: .go, factories: [.go: { backend }])
        let deviceID = try MTPDeviceID(validating: "usb:001:002")

        let session = try router.openSession(for: deviceID)
        XCTAssertEqual(backend.initializeCount, 1)
        XCTAssertEqual(backend.shutdownCount, 0)

        session.close()
        XCTAssertEqual(backend.shutdownCount, 1)
    }

    func testFailedOpenShutsDownBackendAndReleasesRouter() throws {
        let backend = FakeMTPBackend(providerKind: .go)
        backend.openError = .noDevice
        let router = MTPBackendRouter(initialProvider: .go, factories: [.go: { backend }])
        let deviceID = try MTPDeviceID(validating: "usb:001:002")

        XCTAssertThrowsError(try router.openSession(for: deviceID)) {
            XCTAssertEqual($0 as? MTPCoreError, .noDevice)
        }
        XCTAssertEqual(backend.initializeCount, 1)
        XCTAssertEqual(backend.shutdownCount, 1)

        backend.openError = nil
        XCTAssertNoThrow(try router.openSession(for: deviceID).close())
    }

    func testCloseWaitsForInFlightDelegation() throws {
        let backend = FakeMTPBackend(providerKind: .go)
        let router = MTPBackendRouter(initialProvider: .go, factories: [.go: { backend }])
        let deviceID = try MTPDeviceID(validating: "usb:001:002")
        let storageID = try MTPStorageID(validating: 1)
        let session = try router.openSession(for: deviceID)
        let sessionBox = UncheckedSessionBox(session)
        let operationStarted = DispatchSemaphore(value: 0)
        let allowOperationToFinish = DispatchSemaphore(value: 0)
        let operationFinished = DispatchSemaphore(value: 0)
        let closeFinished = DispatchSemaphore(value: 0)

        backend.sessions.single?.listObjectsHandler = { _, _ in
            operationStarted.signal()
            allowOperationToFinish.wait()
            return []
        }

        DispatchQueue.global().async {
            _ = try? sessionBox.value.listObjects(storageID: storageID, parentID: .root)
            operationFinished.signal()
        }
        XCTAssertEqual(operationStarted.wait(timeout: .now() + 1), .success)

        DispatchQueue.global().async {
            sessionBox.value.close()
            closeFinished.signal()
        }

        let earlyClose = closeFinished.wait(timeout: .now() + 0.1)
        XCTAssertEqual(earlyClose, .timedOut)
        allowOperationToFinish.signal()
        XCTAssertEqual(operationFinished.wait(timeout: .now() + 1), .success)
        if earlyClose == .timedOut {
            XCTAssertEqual(closeFinished.wait(timeout: .now() + 1), .success)
        }
    }
}

private extension Array {
    var single: Element? {
        count == 1 ? self[0] : nil
    }
}

private final class UncheckedSessionBox: @unchecked Sendable {
    let value: any MTPBackendSession

    init(_ value: any MTPBackendSession) {
        self.value = value
    }
}
