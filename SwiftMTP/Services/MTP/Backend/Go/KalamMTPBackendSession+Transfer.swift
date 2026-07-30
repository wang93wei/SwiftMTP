import Foundation

private nonisolated final class KalamCancellationGate: @unchecked Sendable {
    typealias Cancel = (UnsafeMutablePointer<CChar>) -> Void

    private let lock = NSLock()
    private let taskID: String
    private let cancelTask: Cancel
    private let abortTask: (UnsafeMutablePointer<CChar>) -> Int32
    private var active = true

    init(
        taskID: String,
        cancel: @escaping Cancel,
        abort: @escaping (UnsafeMutablePointer<CChar>) -> Int32
    ) {
        self.taskID = taskID
        self.cancelTask = cancel
        self.abortTask = abort
    }

    func cancel() {
        lock.withLock {
            guard active else {
                return
            }
            taskID.withCString {
                cancelTask(UnsafeMutablePointer(mutating: $0))
            }
        }
    }

    func finish() {
        lock.withLock {
            guard active else {
                return
            }
            active = false
            taskID.withCString {
                _ = abortTask(UnsafeMutablePointer(mutating: $0))
            }
        }
    }
}

extension KalamMTPBackendSession {
    nonisolated func download(
        _ request: MTPDownloadRequest,
        progress: @escaping MTPTransferProgress,
        cancellation: MTPCancellationToken
    ) throws {
        try withOpenSession {
            let taskID = UUID().uuidString
            guard taskID.withCString({
                transferABI.prepare(UnsafeMutablePointer(mutating: $0)) != 0
            }) else {
                throw MTPCoreError.invalidInput("Go transfer task preparation failed")
            }
            let cancellationGate = KalamCancellationGate(
                taskID: taskID,
                cancel: transferABI.cancel,
                abort: transferABI.abort
            )
            let cancellationRegistration = cancellation.onCancel {
                cancellationGate.cancel()
            }
            defer {
                cancellationRegistration?.invalidate()
                cancellationGate.finish()
            }
            try cancellation.throwIfCancelled()
            let response: KalamTransferResponseDTO = try withTokenPointer { tokenPointer in
                try request.destinationURL.path.withCString { pathPointer in
                    try taskID.withCString { taskPointer in
                        try decodeKalamResponse(
                            transferABI.download(
                                tokenPointer,
                                request.objectID.rawValue,
                                UnsafeMutablePointer(mutating: pathPointer),
                                UnsafeMutablePointer(mutating: taskPointer),
                                progress
                            ),
                            abi: fileSystemABI
                        )
                    }
                }
            }
            let transferredBytes = try validateKalamTransferSuccess(response)
            if let expectedSize = request.expectedSize, transferredBytes != expectedSize {
                throw MTPCoreError.protocolViolation(
                    "Go download byte count does not match the typed request"
                )
            }
        }
    }

    nonisolated func upload(
        _ request: MTPUploadRequest,
        progress: @escaping MTPTransferProgress,
        cancellation: MTPCancellationToken
    ) throws {
        try withOpenSession {
            let taskID = UUID().uuidString
            guard taskID.withCString({
                transferABI.prepare(UnsafeMutablePointer(mutating: $0)) != 0
            }) else {
                throw MTPCoreError.invalidInput("Go transfer task preparation failed")
            }
            let cancellationGate = KalamCancellationGate(
                taskID: taskID,
                cancel: transferABI.cancel,
                abort: transferABI.abort
            )
            let cancellationRegistration = cancellation.onCancel {
                cancellationGate.cancel()
            }
            defer {
                cancellationRegistration?.invalidate()
                cancellationGate.finish()
            }
            try cancellation.throwIfCancelled()
            let response: KalamTransferResponseDTO = try withTokenPointer { tokenPointer in
                try request.sourceURL.path.withCString { pathPointer in
                    try request.name.withCString { namePointer in
                        try taskID.withCString { taskPointer in
                            try decodeKalamResponse(
                                transferABI.upload(
                                    tokenPointer,
                                    request.storageID.rawValue,
                                    request.parentID.rawValue,
                                    UnsafeMutablePointer(mutating: pathPointer),
                                    UnsafeMutablePointer(mutating: namePointer),
                                    request.size,
                                    UnsafeMutablePointer(mutating: taskPointer),
                                    progress
                                ),
                                abi: fileSystemABI
                            )
                        }
                    }
                }
            }
            let transferredBytes = try validateKalamTransferSuccess(response)
            guard transferredBytes == request.size else {
                throw MTPCoreError.protocolViolation(
                    "Go upload byte count does not match the typed request"
                )
            }
        }
    }
}
