import Foundation
import OSLog

extension KalamMTPBackendSession {
    nonisolated func listObjects(
        storageID: MTPStorageID,
        parentID: MTPObjectID
    ) throws -> MTPDirectoryListing {
        try withOpenSession {
            let response: KalamListResponseDTO = try withTokenPointer { tokenPointer in
                try decodeKalamResponse(
                    fileSystemABI.list(
                        tokenPointer,
                        storageID.rawValue,
                        parentID.rawValue
                    ),
                    abi: fileSystemABI
                )
            }
            try validateKalamSuccess(response.ok, errorCode: response.error)
            let objects = try (response.files ?? []).map {
                try $0.object(expectedStorageID: storageID)
            }
            let failures = try (response.failures ?? []).map {
                try $0.failure(
                    deviceID: deviceID,
                    expectedStorageID: storageID,
                    expectedParentID: parentID
                )
            }
            for failure in failures {
                MTPLog.fileSystem.warning(
                    "Go ObjectInfo skipped for object \(failure.objectID.rawValue, privacy: .public): \(String(describing: failure.error), privacy: .public)"
                )
            }
            return MTPDirectoryListing(objects: objects, failures: failures)
        }
    }

    nonisolated func createFolder(
        storageID: MTPStorageID,
        parentID: MTPObjectID,
        name: String
    ) throws -> MTPObjectID {
        _ = try MTPObjectInfoDataset.folder(
            storageID: storageID,
            parentObject: parentID,
            name: name
        )
        return try withOpenSession {
            let response: KalamMutationResponseDTO = try withTokenPointer { tokenPointer in
                try name.withCString { namePointer in
                    try decodeKalamResponse(
                        fileSystemABI.create(
                            tokenPointer,
                            storageID.rawValue,
                            parentID.rawValue,
                            UnsafeMutablePointer(mutating: namePointer)
                        ),
                        abi: fileSystemABI
                    )
                }
            }
            try validateKalamSuccess(response.ok, errorCode: response.error)
            guard let handle = response.objectId else {
                throw MTPCoreError.protocolViolation(
                    "Go create-folder response omitted its object ID"
                )
            }
            return try MTPObjectID(validating: handle)
        }
    }

    nonisolated func deleteObject(_ objectID: MTPObjectID) throws {
        try withOpenSession {
            let response: KalamMutationResponseDTO = try withTokenPointer { tokenPointer in
                try decodeKalamResponse(
                    fileSystemABI.delete(tokenPointer, objectID.rawValue),
                    abi: fileSystemABI
                )
            }
            try validateKalamSuccess(response.ok, errorCode: response.error)
        }
    }

    nonisolated func refreshStorage(_ storageID: MTPStorageID) throws -> MTPStorage {
        try withOpenSession {
            let response: KalamMutationResponseDTO = try withTokenPointer { tokenPointer in
                try decodeKalamResponse(
                    fileSystemABI.refresh(tokenPointer, storageID.rawValue),
                    abi: fileSystemABI
                )
            }
            try validateKalamSuccess(response.ok, errorCode: response.error)
            guard let storage = response.storage else {
                throw MTPCoreError.protocolViolation(
                    "Go refresh-storage response omitted storage metadata"
                )
            }
            return try storage.storage()
        }
    }
}
