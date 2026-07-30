import Foundation

nonisolated extension SwiftMTPBackendSession {
    func download(
        _ request: MTPDownloadRequest,
        progress: @escaping (UInt64) -> Void,
        cancellation: MTPCancellationToken
    ) throws {
        try withOpenSession {
            let destination = try makeDownloadDestination(
                request.destinationURL,
                request.replacementPolicy
            )
            do {
                let result = try discoverySession.download(
                    objectID: request.objectID,
                    sink: destination,
                    progress: progress,
                    cancellation: cancellation
                )
                if let expectedSize = request.expectedSize,
                   result.transferredByteCount != expectedSize {
                    throw MTPCoreError.protocolViolation(
                        "Swift download byte count does not match the typed request"
                    )
                }
                try destination.finish(cancellation: cancellation)
            } catch {
                destination.abort()
                throw error
            }
        }
    }

    func upload(
        _ request: MTPUploadRequest,
        progress: @escaping (UInt64) -> Void,
        cancellation: MTPCancellationToken
    ) throws {
        try withOpenSession {
            try cancellation.throwIfCancelled()
            let source = try makeUploadSource(request)
            defer { source.close() }
            guard source.size == request.size else {
                throw MTPCoreError.invalidInput(
                    "upload source size does not match the typed request"
                )
            }
            let storage = try discoverySession.getStorageInfo(request.storageID)
            guard request.size <= storage.freeSpaceInBytes else {
                throw MTPCoreError.invalidInput(
                    "upload source exceeds available storage space"
                )
            }
            let result = try discoverySession.upload(
                storageID: request.storageID,
                parentID: request.parentID,
                name: request.name,
                size: source.size,
                modificationDateString: source.modificationDateString,
                source: source,
                progress: progress,
                cancellation: cancellation
            )
            guard result.transferredByteCount == request.size else {
                throw MTPCoreError.protocolViolation(
                    "Swift upload byte count does not match the typed request"
                )
            }
        }
    }
}
