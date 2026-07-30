import Foundation

nonisolated extension MTPDeviceSession {
    func upload(
        storageID: MTPStorageID,
        parentID: MTPObjectID,
        name: String,
        size: UInt64,
        modificationDateString: String,
        source: any MTPStreamSource,
        progress: @escaping MTPTransferProgress,
        cancellation: MTPCancellationToken
    ) throws -> MTPUploadResult {
        try lock.withLock {
            guard state == .open else {
                throw MTPCoreError.disconnected
            }
            try cancellation.throwIfCancelled()
            let dataset = try MTPObjectInfoDataset.file(
                storageID: storageID,
                parentObject: parentID,
                name: name,
                size: size,
                modificationDateString: modificationDateString
            )
            let objectID = try sendObjectInfoLocked(
                storageID: storageID,
                parentID: parentID,
                dataset: dataset,
                cancellation: cancellation
            )

            do {
                return try sendObjectLocked(
                    objectID: objectID,
                    size: size,
                    source: source,
                    progress: progress,
                    cancellation: cancellation
                )
            } catch {
                let primaryError = uploadCoreError(error)
                compensateUploadLocked(
                    objectID: objectID,
                    primaryError: primaryError
                )
                throw primaryError
            }
        }
    }

    private func sendObjectInfoLocked(
        storageID: MTPStorageID,
        parentID: MTPObjectID,
        dataset: MTPObjectInfoDataset,
        cancellation: MTPCancellationToken
    ) throws -> MTPObjectID {
        let result: MTPTransactionResult
        do {
            result = try executeLocked(
                operation: .sendObjectInfo,
                parameters: [storageID.rawValue, parentID.rawValue],
                phase: .outbound(try dataset.encoded()),
                cancellation: cancellation
            )
        } catch {
            if shouldInvalidate(error) {
                state = .invalid
            }
            throw error
        }
        guard result.responseParameters.count == 3,
              result.responseParameters[0] == storageID.rawValue,
              result.responseParameters[1] == parentID.rawValue,
              result.responseParameters[2] != 0 else {
            state = .invalid
            throw MTPCoreError.protocolViolation(
                "SendObjectInfo response must contain matching storage, parent, and object"
            )
        }
        return try MTPObjectID(validating: result.responseParameters[2])
    }
}
