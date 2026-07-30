import Foundation
import OSLog

nonisolated extension SwiftMTPBackendSession {
    func listObjects(
        storageID: MTPStorageID,
        parentID: MTPObjectID
    ) throws -> MTPDirectoryListing {
        try withOpenSession {
            let handles = try discoverySession.getObjectHandles(
                storageID: storageID,
                parentID: parentID
            )
            var objects: [MTPObject] = []
            var failures: [MTPObjectFailure] = []
            for handle in handles {
                do {
                    let info = try discoverySession.getObjectInfo(handle)
                    guard info.storageID == storageID else {
                        throw MTPCoreError.protocolViolation(
                            "ObjectInfo storage does not match listing storage"
                        )
                    }
                    objects.append(
                        MTPObject(
                            id: handle,
                            parentID: info.parentObject,
                            storageID: info.storageID,
                            name: info.filename,
                            size: info.objectSize,
                            isFolder: info.objectFormat == 0x3001,
                            modificationDate: info.modificationDate
                        )
                    )
                } catch let error as MTPCoreError {
                    guard case .response(let responseCode) = error,
                          responseCode == .invalidObjectHandle else {
                        throw error
                    }
                    failures.append(
                        MTPObjectFailure(
                            deviceID: deviceID,
                            storageID: storageID,
                            parentID: parentID,
                            objectID: handle,
                            stage: .objectInfo,
                            error: error
                        )
                    )
                    MTPLog.fileSystem.warning(
                        "ObjectInfo skipped for object \(handle.rawValue, privacy: .public): \(String(describing: error), privacy: .public)"
                    )
                }
            }
            return MTPDirectoryListing(objects: objects, failures: failures)
        }
    }

    func createFolder(
        storageID: MTPStorageID,
        parentID: MTPObjectID,
        name: String
    ) throws -> MTPObjectID {
        try withOpenSession {
            return try discoverySession.createFolder(
                storageID: storageID,
                parentID: parentID,
                name: name
            )
        }
    }

    func deleteObject(_ objectID: MTPObjectID) throws {
        try withOpenSession {
            try discoverySession.deleteObject(objectID)
        }
    }

    func refreshStorage(_ storageID: MTPStorageID) throws -> MTPStorage {
        try withOpenSession {
            let info = try discoverySession.getStorageInfo(storageID)
            return MTPStorage(
                id: storageID,
                description: info.description,
                freeSpace: info.freeSpaceInBytes,
                maxCapacity: info.maxCapacity
            )
        }
    }
}
