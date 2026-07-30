import Foundation

struct FileSystemDeleteFailure: Equatable, Sendable {
    let objectID: MTPObjectID
    let error: MTPCoreError
}

struct FileSystemBatchDeleteResult: Equatable, Sendable {
    let succeededObjectIDs: [MTPObjectID]
    let failures: [FileSystemDeleteFailure]
}

protocol FileSystemManaging: Actor {
    func getFileList(
        for device: Device,
        parentID: MTPObjectID,
        storageID: MTPStorageID
    ) async throws -> [FileItem]
    func getRootFiles(for device: Device) async throws -> [FileItem]
    func getChildrenFiles(for device: Device, parent: FileItem) async throws -> [FileItem]
    func createFolder(
        for device: Device,
        parent: FileItem?,
        name: String
    ) async throws -> MTPObjectID
    func deleteObject(for device: Device, objectID: MTPObjectID) async throws
    func deleteObjects(
        for device: Device,
        objectIDs: [MTPObjectID]
    ) async throws -> FileSystemBatchDeleteResult
    func refreshStorage(for device: Device, storageID: MTPStorageID) async throws -> MTPStorage
    func clearCache() async
    func clearCache(for device: Device) async
}
