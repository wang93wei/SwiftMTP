import Foundation
@testable import SwiftMTP

final class FakeMTPBackend: MTPBackend {
    let providerKind: MTPProviderKind
    private(set) var openedDeviceIDs: [MTPDeviceID] = []
    private(set) var sessions: [FakeMTPBackendSession] = []
    private(set) var initializeCount = 0
    private(set) var shutdownCount = 0
    var openError: MTPCoreError?
    var scanResult = MTPScanResult(snapshots: [], failures: [])

    init(providerKind: MTPProviderKind) {
        self.providerKind = providerKind
    }

    func initialize() throws { initializeCount += 1 }
    func scanDevices() throws -> MTPScanResult {
        scanResult
    }

    func openSession(for deviceID: MTPDeviceID) throws -> any MTPBackendSession {
        if let openError {
            throw openError
        }
        openedDeviceIDs.append(deviceID)
        let session = FakeMTPBackendSession(deviceID: deviceID, providerKind: providerKind)
        sessions.append(session)
        return session
    }

    func shutdown() { shutdownCount += 1 }
}

final class FakeMTPBackendSession: MTPBackendSession {
    let deviceID: MTPDeviceID
    var providerKind: MTPProviderKind
    private(set) var closeCount = 0
    var listObjectsHandler: ((MTPStorageID, MTPObjectID) throws -> MTPDirectoryListing)?
    var downloadHandler: ((
        MTPDownloadRequest,
        MTPTransferProgress,
        MTPCancellationToken
    ) throws -> Void)?
    var uploadHandler: ((
        MTPUploadRequest,
        MTPTransferProgress,
        MTPCancellationToken
    ) throws -> Void)?

    init(deviceID: MTPDeviceID, providerKind: MTPProviderKind) {
        self.deviceID = deviceID
        self.providerKind = providerKind
    }

    func listObjects(
        storageID: MTPStorageID,
        parentID: MTPObjectID
    ) throws -> MTPDirectoryListing {
        try listObjectsHandler?(storageID, parentID)
            ?? MTPDirectoryListing(objects: [], failures: [])
    }
    func createFolder(
        storageID: MTPStorageID,
        parentID: MTPObjectID,
        name: String
    ) throws -> MTPObjectID {
        try MTPObjectID(validating: 1)
    }
    func deleteObject(_ objectID: MTPObjectID) throws {}
    func download(
        _ request: MTPDownloadRequest,
        progress: @escaping MTPTransferProgress,
        cancellation: MTPCancellationToken
    ) throws {
        try downloadHandler?(request, progress, cancellation)
    }
    func upload(
        _ request: MTPUploadRequest,
        progress: @escaping MTPTransferProgress,
        cancellation: MTPCancellationToken
    ) throws {
        try uploadHandler?(request, progress, cancellation)
    }
    func refreshStorage(_ storageID: MTPStorageID) throws -> MTPStorage {
        MTPStorage(id: storageID, description: "", freeSpace: 0, maxCapacity: 0)
    }
    func close() { closeCount += 1 }
}
