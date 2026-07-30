import Foundation
import XCTest
@testable import SwiftMTP

final class MTPConnectionCoordinatorTransferTests: XCTestCase {
    func testTransfersForwardOnlyToMatchingProviderBoundActiveSession() throws {
        let backend = FakeMTPBackend(providerKind: .go)
        let coordinator = MTPConnectionCoordinator(factories: [.go: { backend }])
        let appID = UUID()
        let deviceID = try MTPDeviceID(validating: "go:7")
        try coordinator.register(
            appDeviceID: appID,
            snapshot: snapshot(deviceID),
            providerKind: .go
        )
        try coordinator.selectDevice(appID)
        let session = try XCTUnwrap(backend.sessions.first)
        let objectID = try MTPObjectID(validating: 9)
        let storageID = try MTPStorageID(validating: 1)
        let cancellation = MTPCancellationToken()
        let download = MTPDownloadRequest(
            objectID: objectID,
            destinationURL: URL(fileURLWithPath: "/tmp/download.bin"),
            expectedSize: 4
        )
        let upload = MTPUploadRequest(
            storageID: storageID,
            parentID: .root,
            sourceURL: URL(fileURLWithPath: "/tmp/upload.bin"),
            name: "upload.bin",
            size: 5
        )
        var receivedDownload: MTPDownloadRequest?
        var receivedUpload: MTPUploadRequest?
        var receivedCancellation: [MTPCancellationToken] = []
        var progressValues: [UInt64] = []
        session.downloadHandler = { request, progress, token in
            receivedDownload = request
            receivedCancellation.append(token)
            progress(4)
        }
        session.uploadHandler = { request, progress, token in
            receivedUpload = request
            receivedCancellation.append(token)
            progress(5)
        }

        try coordinator.download(
            appDeviceID: appID,
            deviceID: deviceID,
            request: download,
            progress: { progressValues.append($0) },
            cancellation: cancellation
        )
        try coordinator.upload(
            appDeviceID: appID,
            deviceID: deviceID,
            request: upload,
            progress: { progressValues.append($0) },
            cancellation: cancellation
        )

        XCTAssertEqual(receivedDownload, download)
        XCTAssertEqual(receivedUpload, upload)
        XCTAssertTrue(receivedCancellation.allSatisfy { $0 === cancellation })
        XCTAssertEqual(progressValues, [4, 5])
        coordinator.close()
    }

    func testWrongIdentityOrProviderNeverCallsTransferSession() throws {
        let backend = FakeMTPBackend(providerKind: .go)
        let coordinator = MTPConnectionCoordinator(factories: [.go: { backend }])
        let appID = UUID()
        let deviceID = try MTPDeviceID(validating: "go:7")
        try coordinator.register(
            appDeviceID: appID,
            snapshot: snapshot(deviceID),
            providerKind: .go
        )
        try coordinator.selectDevice(appID)
        let session = try XCTUnwrap(backend.sessions.first)
        var callCount = 0
        session.downloadHandler = { _, _, _ in callCount += 1 }
        let request = MTPDownloadRequest(
            objectID: try MTPObjectID(validating: 9),
            destinationURL: URL(fileURLWithPath: "/tmp/download.bin"),
            expectedSize: nil
        )

        XCTAssertThrowsError(
            try coordinator.download(
                appDeviceID: UUID(),
                deviceID: deviceID,
                request: request,
                progress: { _ in },
                cancellation: MTPCancellationToken()
            )
        )
        XCTAssertThrowsError(
            try coordinator.download(
                appDeviceID: appID,
                deviceID: try MTPDeviceID(validating: "go:8"),
                request: request,
                progress: { _ in },
                cancellation: MTPCancellationToken()
            )
        )
        session.providerKind = .swift
        XCTAssertThrowsError(
            try coordinator.download(
                appDeviceID: appID,
                deviceID: deviceID,
                request: request,
                progress: { _ in },
                cancellation: MTPCancellationToken()
            )
        )
        XCTAssertEqual(callCount, 0)
        coordinator.close()
    }

    func testTerminalTransferFailureInvalidatesExactlyOnceWithoutReplay() throws {
        let backend = FakeMTPBackend(providerKind: .go)
        let coordinator = MTPConnectionCoordinator(factories: [.go: { backend }])
        let appID = UUID()
        let deviceID = try MTPDeviceID(validating: "go:7")
        try coordinator.register(
            appDeviceID: appID,
            snapshot: snapshot(deviceID),
            providerKind: .go
        )
        try coordinator.selectDevice(appID)
        let session = try XCTUnwrap(backend.sessions.first)
        var callCount = 0
        session.uploadHandler = { _, _, _ in
            callCount += 1
            throw MTPCoreError.timeout
        }
        let request = MTPUploadRequest(
            storageID: try MTPStorageID(validating: 1),
            parentID: .root,
            sourceURL: URL(fileURLWithPath: "/tmp/upload.bin"),
            name: "upload.bin",
            size: 5
        )

        XCTAssertThrowsError(
            try coordinator.upload(
                appDeviceID: appID,
                deviceID: deviceID,
                request: request,
                progress: { _ in },
                cancellation: MTPCancellationToken()
            )
        ) {
            XCTAssertEqual($0 as? MTPCoreError, .timeout)
        }
        XCTAssertEqual(callCount, 1)
        XCTAssertEqual(session.closeCount, 1)
        XCTAssertEqual(backend.shutdownCount, 1)
        XCTAssertThrowsError(
            try coordinator.upload(
                appDeviceID: appID,
                deviceID: deviceID,
                request: request,
                progress: { _ in },
                cancellation: MTPCancellationToken()
            )
        )
        XCTAssertEqual(callCount, 1)
        coordinator.close()
        XCTAssertEqual(session.closeCount, 1)
        XCTAssertEqual(backend.shutdownCount, 1)
    }

    func testSwitchAndClosePreventTransfersThroughRetiredSessions() throws {
        let backend = FakeMTPBackend(providerKind: .go)
        let coordinator = MTPConnectionCoordinator(factories: [.go: { backend }])
        let firstAppID = UUID()
        let secondAppID = UUID()
        let firstDeviceID = try MTPDeviceID(validating: "go:7")
        let secondDeviceID = try MTPDeviceID(validating: "go:8")
        try coordinator.register(
            appDeviceID: firstAppID,
            snapshot: snapshot(firstDeviceID),
            providerKind: .go
        )
        try coordinator.register(
            appDeviceID: secondAppID,
            snapshot: snapshot(secondDeviceID),
            providerKind: .go
        )
        let request = MTPDownloadRequest(
            objectID: try MTPObjectID(validating: 9),
            destinationURL: URL(fileURLWithPath: "/tmp/download.bin"),
            expectedSize: nil
        )

        try coordinator.selectDevice(firstAppID)
        let firstSession = try XCTUnwrap(backend.sessions.first)
        var firstCalls = 0
        firstSession.downloadHandler = { _, _, _ in firstCalls += 1 }
        try coordinator.selectDevice(secondAppID)
        let secondSession = try XCTUnwrap(backend.sessions.last)
        var secondCalls = 0
        secondSession.downloadHandler = { _, _, _ in secondCalls += 1 }

        XCTAssertThrowsError(
            try coordinator.download(
                appDeviceID: firstAppID,
                deviceID: firstDeviceID,
                request: request,
                progress: { _ in },
                cancellation: MTPCancellationToken()
            )
        )
        XCTAssertEqual(firstCalls, 0)
        XCTAssertEqual(firstSession.closeCount, 1)

        coordinator.close()
        XCTAssertThrowsError(
            try coordinator.download(
                appDeviceID: secondAppID,
                deviceID: secondDeviceID,
                request: request,
                progress: { _ in },
                cancellation: MTPCancellationToken()
            )
        )
        XCTAssertEqual(secondCalls, 0)
        XCTAssertEqual(secondSession.closeCount, 1)
    }

    func testUnsupportedAndLocalValidationFailuresKeepPinnedProviderActive() throws {
        let backend = FakeMTPBackend(providerKind: .go)
        let coordinator = MTPConnectionCoordinator(factories: [.go: { backend }])
        let appID = UUID()
        let deviceID = try MTPDeviceID(validating: "go:7")
        try coordinator.register(
            appDeviceID: appID,
            snapshot: snapshot(deviceID),
            providerKind: .go
        )
        try coordinator.selectDevice(appID)
        let session = try XCTUnwrap(backend.sessions.first)
        var errors: [MTPCoreError] = [.unsupportedDevice, .localFileIO("source")]
        session.uploadHandler = { _, _, _ in
            if !errors.isEmpty {
                throw errors.removeFirst()
            }
        }
        let request = MTPUploadRequest(
            storageID: try MTPStorageID(validating: 1),
            parentID: .root,
            sourceURL: URL(fileURLWithPath: "/tmp/upload.bin"),
            name: "upload.bin",
            size: 5
        )

        for expected in [MTPCoreError.unsupportedDevice, .localFileIO("source")] {
            XCTAssertThrowsError(
                try coordinator.upload(
                    appDeviceID: appID,
                    deviceID: deviceID,
                    request: request,
                    progress: { _ in },
                    cancellation: MTPCancellationToken()
                )
            ) {
                XCTAssertEqual($0 as? MTPCoreError, expected)
            }
        }
        XCTAssertNoThrow(
            try coordinator.upload(
                appDeviceID: appID,
                deviceID: deviceID,
                request: request,
                progress: { _ in },
                cancellation: MTPCancellationToken()
            )
        )
        XCTAssertEqual(backend.openedDeviceIDs, [deviceID])
        XCTAssertEqual(session.closeCount, 0)
        XCTAssertEqual(backend.shutdownCount, 0)
        coordinator.close()
    }

    private func snapshot(_ deviceID: MTPDeviceID) -> MTPDeviceSnapshot {
        MTPDeviceSnapshot(
            deviceID: deviceID,
            name: "Phone",
            manufacturer: "Acme",
            model: "P",
            storages: []
        )
    }
}
