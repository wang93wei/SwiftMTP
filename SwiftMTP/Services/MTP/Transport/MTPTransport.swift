import Foundation

nonisolated protocol MTPTransport {
    /// Executes one serialized raw MTP transaction.
    /// Response fragments preserve transport packet boundaries for session decoding.
    func transact(
        _ request: Data,
        cancellation: MTPCancellationToken
    ) throws -> [Data]
}

/// Traditional lock-backed token used by blocking USB operations.
/// The unchecked conformance is narrowly audited: all mutable state is under `lock`.
nonisolated final class MTPCancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var callbacks: [() -> Void] = []

    var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    func cancel() {
        let callbacksToRun: [() -> Void] = lock.withLock {
            guard !cancelled else {
                return []
            }
            cancelled = true
            let callbacksToRun = callbacks
            callbacks.removeAll()
            return callbacksToRun
        }
        callbacksToRun.forEach { $0() }
    }

    func onCancel(_ callback: @escaping () -> Void) {
        let shouldRunNow = lock.withLock {
            if cancelled {
                return true
            }
            callbacks.append(callback)
            return false
        }
        if shouldRunNow {
            callback()
        }
    }

    func throwIfCancelled() throws {
        if isCancelled {
            throw MTPCoreError.cancelled
        }
    }
}
