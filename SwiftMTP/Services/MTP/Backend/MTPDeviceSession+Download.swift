import Foundation

nonisolated extension MTPDeviceSession {
    func download(
        objectID: MTPObjectID,
        sink: any MTPStreamSink,
        progress: @escaping MTPTransferProgress,
        cancellation: MTPCancellationToken
    ) throws -> MTPDownloadResult {
        try lock.withLock {
            guard state == .open else {
                throw MTPCoreError.disconnected
            }
            do {
                try cancellation.throwIfCancelled()
                let objectInfo: MTPObjectInfoDataset = try executeInboundLocked(
                    operation: .getObjectInfo,
                    parameters: [objectID.rawValue],
                    cancellation: cancellation
                ) {
                    try MTPObjectInfoDataset.decode($0)
                }
                let expectedByteCount = try resolvedObjectSizeLocked(
                    objectID: objectID,
                    objectInfo: objectInfo,
                    cancellation: cancellation
                )
                return try receiveObjectLocked(
                    objectID: objectID,
                    expectedByteCount: expectedByteCount,
                    sink: sink,
                    progress: progress,
                    cancellation: cancellation
                )
            } catch {
                if shouldInvalidateDownload(error) {
                    state = .invalid
                }
                throw error
            }
        }
    }

    private func receiveObjectLocked(
        objectID: MTPObjectID,
        expectedByteCount: UInt64?,
        sink: any MTPStreamSink,
        progress: @escaping MTPTransferProgress,
        cancellation: MTPCancellationToken
    ) throws -> MTPDownloadResult {
        let transactionID = try MTPTransactionID(
            validating: consumeTransactionID()
        )
        let request = try command(
            operation: .getObject,
            transactionID: transactionID,
            parameters: [objectID.rawValue]
        )
        let progressSink = MTPDownloadProgressSink(
            downstream: sink,
            progress: progress
        )
        let result = try transport.receive(
            request,
            operationCode: .getObject,
            transactionID: transactionID,
            expectedPayloadLength: expectedByteCount,
            sink: progressSink,
            cancellation: cancellation
        )
        try cancellation.throwIfCancelled()
        guard result.responseCode == .ok else {
            throw MTPCoreError.response(code: result.responseCode)
        }
        guard result.responseParameters.isEmpty else {
            throw MTPCoreError.protocolViolation(
                "GetObject response unexpectedly contained parameters"
            )
        }
        guard result.transferredByteCount == progressSink.transferredByteCount else {
            throw MTPCoreError.protocolViolation(
                "GetObject transport and sink byte counts differ"
            )
        }
        if let expectedByteCount,
           result.transferredByteCount != expectedByteCount {
            throw MTPCoreError.protocolViolation(
                "GetObject byte count does not match the known object size"
            )
        }
        return MTPDownloadResult(
            expectedByteCount: expectedByteCount,
            transferredByteCount: result.transferredByteCount
        )
    }

    private func shouldInvalidateDownload(_ error: Error) -> Bool {
        if let coreError = error as? MTPCoreError,
           case .localFileIO = coreError {
            return true
        }
        return shouldInvalidate(error)
    }
}

private nonisolated final class MTPDownloadProgressSink: MTPStreamSink {
    let downstream: any MTPStreamSink
    let progress: MTPTransferProgress
    private(set) var transferredByteCount: UInt64 = 0

    init(
        downstream: any MTPStreamSink,
        progress: @escaping MTPTransferProgress
    ) {
        self.downstream = downstream
        self.progress = progress
    }

    func write(_ data: Data) throws {
        guard UInt64(data.count) <= UInt64.max - transferredByteCount else {
            throw MTPCoreError.protocolViolation("GetObject byte count overflow")
        }
        try downstream.write(data)
        transferredByteCount += UInt64(data.count)
        progress(transferredByteCount)
    }
}
