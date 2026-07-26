import CLibUSB
import Foundation
import OSLog

/// Owns the process-wide libusb context and the event-pump lifetime.
/// Mutable state and the raw context pointer are protected by `condition`.
nonisolated final class LibUSBContext: @unchecked Sendable {
    private let functions: LibUSBFunctionTable
    private let condition = NSCondition()
    private let eventQueue = DispatchQueue(label: "com.AlanWang.SwiftMTP.libusb.events")
    private let startsEventLoop: Bool
    private var context: OpaquePointer?
    private var shuttingDown = false
    private var activeTransfers: [ObjectIdentifier: LibUSBTransfer] = [:]
    private var openingHandleCount = 0
    private var openHandles: [ObjectIdentifier: WeakLibUSBDeviceHandle] = [:]

    init(
        functions: LibUSBFunctionTable = LibUSBFunctionTable(),
        startsEventLoop: Bool = true
    ) throws {
        self.functions = functions
        self.startsEventLoop = startsEventLoop
        var context: OpaquePointer?
        let result = functions.initialize(&context)
        guard result == 0, let context else {
            throw mtpErrorFromLibUSB(result)
        }
        self.context = context
        if startsEventLoop {
            eventQueue.async { [weak self] in
                self?.runEventLoop()
            }
        }
    }

    deinit {
        shutdown()
    }

    func shutdown() {
        let transfers: [LibUSBTransfer] = condition.withLock {
            guard !shuttingDown, context != nil else {
                return []
            }
            shuttingDown = true
            return Array(activeTransfers.values)
        }
        transfers.forEach { $0.requestCancellationFromContext() }

        condition.lock()
        while !activeTransfers.isEmpty || openingHandleCount != 0 {
            condition.wait()
        }
        let handles = openHandles.values.compactMap(\.value)
        condition.unlock()

        handles.forEach { $0.close() }

        condition.lock()
        while openHandles.values.contains(where: { $0.value != nil }) {
            condition.wait()
        }
        let contextToExit = context
        context = nil
        condition.broadcast()
        condition.unlock()

        if startsEventLoop {
            eventQueue.sync {}
        }
        if let contextToExit {
            functions.exit(contextToExit)
            MTPLog.usb.debug("libusb context exited")
        }
    }

    func rawContextForEnumeration() throws -> OpaquePointer {
        try condition.withLock {
            guard !shuttingDown, let context else {
                throw MTPCoreError.disconnected
            }
            return context
        }
    }

    func beginHandleCreation() throws {
        try condition.withLock {
            guard !shuttingDown, context != nil else {
                throw MTPCoreError.disconnected
            }
            openingHandleCount += 1
        }
    }

    func completeHandleCreation(_ handle: LibUSBDeviceHandle) {
        condition.withLock {
            openingHandleCount -= 1
            openHandles[ObjectIdentifier(handle)] = WeakLibUSBDeviceHandle(handle)
            condition.broadcast()
        }
    }

    func cancelHandleCreation() {
        condition.withLock {
            openingHandleCount -= 1
            condition.broadcast()
        }
    }

    func unregister(_ handle: LibUSBDeviceHandle) {
        condition.withLock {
            openHandles.removeValue(forKey: ObjectIdentifier(handle))
            condition.broadcast()
        }
    }

    func register(_ transfer: LibUSBTransfer) throws {
        try condition.withLock {
            guard !shuttingDown, context != nil else {
                throw MTPCoreError.cancelled
            }
            activeTransfers[ObjectIdentifier(transfer)] = transfer
        }
    }

    func unregister(_ transfer: LibUSBTransfer) {
        condition.withLock {
            activeTransfers.removeValue(forKey: ObjectIdentifier(transfer))
            condition.broadcast()
        }
    }

    private func runEventLoop() {
        while true {
            let contextToPump: OpaquePointer? = condition.withLock {
                if shuttingDown, activeTransfers.isEmpty {
                    return nil
                }
                return context
            }
            guard let contextToPump else {
                return
            }

            var timeout = timeval(tv_sec: 0, tv_usec: 50_000)
            var completed: Int32 = 0
            let result = functions.handleEventsTimeoutCompleted(
                contextToPump,
                &timeout,
                &completed
            )
            if result < 0, result != Int32(LIBUSB_ERROR_INTERRUPTED.rawValue) {
                MTPLog.usb.error("libusb event loop error: \(result, privacy: .public)")
            }
        }
    }
}

private nonisolated final class WeakLibUSBDeviceHandle {
    weak var value: LibUSBDeviceHandle?

    init(_ value: LibUSBDeviceHandle) {
        self.value = value
    }
}

private extension NSCondition {
    nonisolated func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}
