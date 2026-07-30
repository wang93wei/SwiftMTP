import Foundation

nonisolated extension MTPDeviceSession {
    func sendObjectLocked(
        objectID: MTPObjectID,
        size: UInt64,
        source: any MTPStreamSource,
        progress: @escaping MTPTransferProgress,
        cancellation: MTPCancellationToken
    ) throws -> MTPUploadResult {
        try cancellation.throwIfCancelled()
        let transactionID = try MTPTransactionID(
            validating: consumeTransactionID()
        )
        let request = try command(
            operation: .sendObject,
            transactionID: transactionID,
            parameters: []
        )
        let progressSource = MTPUploadProgressSource(
            downstream: source,
            progress: progress
        )
        let maximumExactPayload = UInt64(UInt32.max) - MTPContainer.headerLength
        var transferredByteCount: UInt64?
        do {
            let result = try transport.send(
                request,
                dataHeader: MTPStreamingDataHeader(
                    operationCode: .sendObject,
                    transactionID: transactionID,
                    payloadLength: size <= maximumExactPayload ? size : nil
                ),
                source: progressSource,
                cancellation: cancellation
            )
            transferredByteCount = result.transferredByteCount
            try cancellation.throwIfCancelled()
            guard result.responseCode == .ok else {
                throw MTPCoreError.response(code: result.responseCode)
            }
            guard result.responseParameters.isEmpty else {
                throw MTPCoreError.protocolViolation(
                    "SendObject response unexpectedly contained parameters"
                )
            }
            guard result.transferredByteCount == size else {
                throw MTPCoreError.protocolViolation(
                    "SendObject byte count does not match the declared source size"
                )
            }
            progressSource.finish(transferredByteCount: result.transferredByteCount)
            return MTPUploadResult(
                objectID: objectID,
                transferredByteCount: result.transferredByteCount
            )
        } catch {
            recordTransactionFailure(
                operation: .sendObject,
                transactionID: transactionID.rawValue,
                error: error,
                transferredByteCount: transferredByteCount
                    ?? progressSource.transferredByteCount
            )
            throw error
        }
    }
}

private nonisolated final class MTPUploadProgressSource: MTPStreamSource {
    let downstream: any MTPStreamSource
    let progress: MTPTransferProgress
    private(set) var transferredByteCount: UInt64 = 0

    init(
        downstream: any MTPStreamSource,
        progress: @escaping MTPTransferProgress
    ) {
        self.downstream = downstream
        self.progress = progress
    }

    var length: UInt64? {
        downstream.length
    }

    func read(maximumLength: Int) throws -> Data {
        let data = try downstream.read(maximumLength: maximumLength)
        guard UInt64(data.count) <= UInt64.max - transferredByteCount else {
            throw MTPCoreError.protocolViolation("SendObject byte count overflow")
        }
        transferredByteCount += UInt64(data.count)
        if !data.isEmpty {
            progress(transferredByteCount)
        }
        return data
    }

    func finish(transferredByteCount: UInt64) {
        guard transferredByteCount > self.transferredByteCount else {
            return
        }
        self.transferredByteCount = transferredByteCount
        progress(transferredByteCount)
    }
}
