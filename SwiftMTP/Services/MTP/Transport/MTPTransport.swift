import Foundation

nonisolated protocol MTPTransport {
    /// Executes one serialized raw MTP transaction.
    /// Response fragments preserve transport packet boundaries for session decoding.
    func transact(
        _ request: Data,
        outboundData: Data?,
        cancellation: MTPCancellationToken
    ) throws -> [Data]

    func receive(
        _ request: Data,
        operationCode: MTPOperationCode,
        transactionID: MTPTransactionID,
        expectedPayloadLength: UInt64?,
        sink: any MTPStreamSink,
        cancellation: MTPCancellationToken
    ) throws -> MTPStreamingTransactionResult

    func send(
        _ request: Data,
        dataHeader: MTPStreamingDataHeader,
        source: any MTPStreamSource,
        cancellation: MTPCancellationToken
    ) throws -> MTPStreamingTransactionResult
}

nonisolated extension MTPTransport {
    func transact(
        _ request: Data,
        cancellation: MTPCancellationToken
    ) throws -> [Data] {
        try transact(request, outboundData: nil, cancellation: cancellation)
    }
}

nonisolated protocol MTPStreamSource: AnyObject {
    /// Known payload length, or nil when the stream ends on an empty read.
    var length: UInt64? { get }

    /// Returns at most `maximumLength` bytes. Empty data marks source terminal.
    func read(maximumLength: Int) throws -> Data
}

nonisolated protocol MTPStreamSink: AnyObject {
    func write(_ data: Data) throws
}

nonisolated struct MTPStreamingTransactionResult: Equatable, Sendable {
    let responseCode: MTPResponseCode
    let responseParameters: [UInt32]
    let transferredByteCount: UInt64
}

/// Traditional lock-backed token used by blocking USB operations.
/// The unchecked conformance is narrowly audited: all mutable state is under `lock`.
nonisolated final class MTPCancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var callbacks: [UUID: () -> Void] = [:]

    var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    var registeredCallbackCount: Int {
        lock.withLock { callbacks.count }
    }

    func cancel() {
        let callbacksToRun: [() -> Void] = lock.withLock {
            guard !cancelled else {
                return []
            }
            cancelled = true
            let callbacksToRun = Array(callbacks.values)
            callbacks.removeAll()
            return callbacksToRun
        }
        callbacksToRun.forEach { $0() }
    }

    @discardableResult
    func onCancel(_ callback: @escaping () -> Void) -> MTPCancellationRegistration? {
        let identifier = UUID()
        let shouldRunNow = lock.withLock {
            if cancelled {
                return true
            }
            callbacks[identifier] = callback
            return false
        }
        if shouldRunNow {
            callback()
            return nil
        }
        return MTPCancellationRegistration { [weak self] in
            self?.removeCallback(identifier)
        }
    }

    func throwIfCancelled() throws {
        if isCancelled {
            throw MTPCoreError.cancelled
        }
    }

    private func removeCallback(_ identifier: UUID) {
        lock.withLock {
            _ = callbacks.removeValue(forKey: identifier)
        }
    }
}

nonisolated final class MTPCancellationRegistration: @unchecked Sendable {
    private let lock = NSLock()
    private var removal: (() -> Void)?

    init(removal: @escaping () -> Void) {
        self.removal = removal
    }

    func invalidate() {
        let removalToRun = lock.withLock {
            defer { removal = nil }
            return removal
        }
        removalToRun?()
    }
}
