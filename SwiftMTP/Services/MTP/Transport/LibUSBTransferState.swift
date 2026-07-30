import CLibUSB
import Foundation

/// Lock-backed lifecycle for one submitted libusb transfer.
nonisolated final class LibUSBTransferState: @unchecked Sendable {
    private let condition = NSCondition()
    private var transfer: UnsafeMutablePointer<libusb_transfer>?
    private var terminalResult: Result<Data, MTPCoreError>?
    private var submitted = false
    private var cancellationRequested = false
    private var started = false

    func begin() throws {
        try condition.withLock {
            guard !started else {
                throw MTPCoreError.busy
            }
            started = true
        }
    }

    func install(_ transfer: UnsafeMutablePointer<libusb_transfer>) {
        condition.withLock {
            self.transfer = transfer
        }
    }

    func markSubmitted() -> UnsafeMutablePointer<libusb_transfer>? {
        condition.withLock {
            submitted = true
            return cancellationRequested && terminalResult == nil
                ? transfer
                : nil
        }
    }

    func requestCancellation() -> UnsafeMutablePointer<libusb_transfer>? {
        condition.withLock {
            guard terminalResult == nil, !cancellationRequested else {
                return nil
            }
            cancellationRequested = true
            return submitted ? transfer : nil
        }
    }

    func complete(with result: Result<Data, MTPCoreError>) {
        condition.withLock {
            guard terminalResult == nil else {
                return
            }
            terminalResult = result
            condition.broadcast()
        }
    }

    func waitForTerminalResult() -> Result<Data, MTPCoreError> {
        condition.withLock {
            while terminalResult == nil {
                condition.wait()
            }
            return terminalResult!
        }
    }

    func discardTransfer() {
        condition.withLock {
            transfer = nil
        }
    }
}

private extension NSCondition {
    nonisolated func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}
