import Foundation

nonisolated enum MTPProviderKind: String, Hashable, Sendable {
    case go
    case `swift`
}

nonisolated struct MTPDeviceSnapshot: Equatable, Sendable {
    let deviceID: MTPDeviceID
    let name: String
    let manufacturer: String
    let model: String
    let storages: [MTPStorage]
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

nonisolated struct MTPDownloadRequest: Equatable, Sendable {
    let objectID: MTPObjectID
    let destinationURL: URL
    let expectedSize: UInt64?
}

nonisolated struct MTPUploadRequest: Equatable, Sendable {
    let storageID: MTPStorageID
    let parentID: MTPObjectID
    let sourceURL: URL
    let name: String
    let size: UInt64
}

nonisolated protocol MTPBackend {
    func initialize() throws
    func scanDevices() throws -> [MTPDeviceSnapshot]
    func openSession(for deviceID: MTPDeviceID) throws -> any MTPBackendSession
    func shutdown()
}

nonisolated protocol MTPBackendSession: AnyObject {
    var deviceID: MTPDeviceID { get }
    var providerKind: MTPProviderKind { get }

    func listObjects(
        storageID: MTPStorageID,
        parentID: MTPObjectID
    ) throws -> [MTPObject]
    func createFolder(
        storageID: MTPStorageID,
        parentID: MTPObjectID,
        name: String
    ) throws -> MTPObjectID
    func deleteObject(_ objectID: MTPObjectID) throws
    func download(
        _ request: MTPDownloadRequest,
        progress: @escaping (UInt64) -> Void,
        cancellation: MTPCancellationToken
    ) throws
    func upload(
        _ request: MTPUploadRequest,
        progress: @escaping (UInt64) -> Void,
        cancellation: MTPCancellationToken
    ) throws
    func refreshStorage(_ storageID: MTPStorageID) throws
    func close()
}
