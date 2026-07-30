import Foundation

nonisolated enum MTPProviderKind: String, Hashable, Sendable {
    case go
    case `swift`
}

nonisolated struct MTPDeviceIdentity: Hashable, Sendable {
    let providerKind: MTPProviderKind
    let deviceID: MTPDeviceID
}

nonisolated struct MTPDeviceSnapshot: Equatable, Sendable {
    let deviceID: MTPDeviceID
    let name: String
    let manufacturer: String
    let model: String
    let storages: [MTPStorage]
}

nonisolated struct MTPScanFailure: Equatable, Sendable {
    enum Stage: String, Equatable, Sendable {
        case device
        case storage
    }

    let deviceID: MTPDeviceID
    let storageID: MTPStorageID?
    let stage: Stage
    let error: MTPCoreError
}

nonisolated struct MTPScanResult: Equatable, Sendable {
    let snapshots: [MTPDeviceSnapshot]
    let failures: [MTPScanFailure]
}

nonisolated struct MTPStorage: Equatable, Sendable {
    let id: MTPStorageID
    let description: String
    let freeSpace: UInt64
    let maxCapacity: UInt64
}

nonisolated struct MTPObject: Equatable, Sendable {
    let id: MTPObjectID
    let parentID: MTPObjectID
    let storageID: MTPStorageID
    let name: String
    let size: UInt64
    let isFolder: Bool
    let modificationDate: Date?
}

nonisolated struct MTPObjectFailure: Equatable, Sendable {
    enum Stage: String, Equatable, Sendable {
        case objectInfo
    }

    let deviceID: MTPDeviceID
    let storageID: MTPStorageID
    let parentID: MTPObjectID
    let objectID: MTPObjectID
    let stage: Stage
    let error: MTPCoreError
}

nonisolated struct MTPDirectoryListing: Equatable, Sendable {
    let objects: [MTPObject]
    let failures: [MTPObjectFailure]
}

nonisolated enum MTPDownloadReplacementPolicy: Equatable, Sendable {
    case replaceExisting
    case failIfExists
}

nonisolated struct MTPDownloadRequest: Equatable, Sendable {
    let objectID: MTPObjectID
    let destinationURL: URL
    let expectedSize: UInt64?
    let replacementPolicy: MTPDownloadReplacementPolicy

    init(
        objectID: MTPObjectID,
        destinationURL: URL,
        expectedSize: UInt64?,
        replacementPolicy: MTPDownloadReplacementPolicy = .replaceExisting
    ) {
        self.objectID = objectID
        self.destinationURL = destinationURL
        self.expectedSize = expectedSize
        self.replacementPolicy = replacementPolicy
    }
}

nonisolated struct MTPUploadRequest: Equatable, Sendable {
    let storageID: MTPStorageID
    let parentID: MTPObjectID
    let sourceURL: URL
    let name: String
    let size: UInt64
}

nonisolated struct MTPUploadResult: Equatable, Sendable {
    let objectID: MTPObjectID
    let transferredByteCount: UInt64
}

nonisolated struct MTPUploadCompensationDiagnostic: Equatable, Sendable {
    enum Outcome: Equatable, Sendable {
        case removed
        case failed(MTPCoreError)
        case skippedOrphanRisk
    }

    let objectID: MTPObjectID
    let primaryError: MTPCoreError
    let outcome: Outcome
}

typealias MTPTransferProgress = (UInt64) -> Void
typealias MTPUploadDiagnosticReporter = (MTPUploadCompensationDiagnostic) -> Void

nonisolated protocol MTPBackend {
    func initialize() throws
    func scanDevices() throws -> MTPScanResult
    func scanDevices(
        reusing snapshots: [MTPDeviceID: MTPDeviceSnapshot]
    ) throws -> MTPScanResult
    func openSession(for deviceID: MTPDeviceID) throws -> any MTPBackendSession
    func shutdown()
}

nonisolated extension MTPBackend {
    func scanDevices(
        reusing snapshots: [MTPDeviceID: MTPDeviceSnapshot]
    ) throws -> MTPScanResult {
        try scanDevices()
    }
}

nonisolated protocol MTPBackendSession: AnyObject {
    var deviceID: MTPDeviceID { get }
    var providerKind: MTPProviderKind { get }

    func listObjects(
        storageID: MTPStorageID,
        parentID: MTPObjectID
    ) throws -> MTPDirectoryListing
    func createFolder(
        storageID: MTPStorageID,
        parentID: MTPObjectID,
        name: String
    ) throws -> MTPObjectID
    func deleteObject(_ objectID: MTPObjectID) throws
    func download(
        _ request: MTPDownloadRequest,
        progress: @escaping MTPTransferProgress,
        cancellation: MTPCancellationToken
    ) throws
    func upload(
        _ request: MTPUploadRequest,
        progress: @escaping MTPTransferProgress,
        cancellation: MTPCancellationToken
    ) throws
    func refreshStorage(_ storageID: MTPStorageID) throws -> MTPStorage
    func close()
}
