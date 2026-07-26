import Foundation
@testable import SwiftMTP

final class FakeMTPBackend: MTPBackend {
    let providerKind: MTPProviderKind
    private(set) var openedDeviceIDs: [MTPDeviceID] = []
    private(set) var sessions: [FakeMTPBackendSession] = []
    private(set) var initializeCount = 0
    private(set) var shutdownCount = 0
    var openError: MTPCoreError?

    init(providerKind: MTPProviderKind) {
        self.providerKind = providerKind
    }

    func initialize() throws { initializeCount += 1 }
    func scanDevices() throws -> [MTPDeviceSnapshot] { [] }

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
    let providerKind: MTPProviderKind
    private(set) var closeCount = 0
    var listObjectsHandler: ((MTPStorageID, MTPObjectID) throws -> [MTPObject])?

    init(deviceID: MTPDeviceID, providerKind: MTPProviderKind) {
        self.deviceID = deviceID
        self.providerKind = providerKind
    }

    func listObjects(storageID: MTPStorageID, parentID: MTPObjectID) throws -> [MTPObject] {
        try listObjectsHandler?(storageID, parentID) ?? []
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
        progress: @escaping (UInt64) -> Void,
        cancellation: MTPCancellationToken
    ) throws {}
    func upload(
        _ request: MTPUploadRequest,
        progress: @escaping (UInt64) -> Void,
        cancellation: MTPCancellationToken
    ) throws {}
    func refreshStorage(_ storageID: MTPStorageID) throws {}
    func close() { closeCount += 1 }
}
