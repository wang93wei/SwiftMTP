import CLibUSB
import Foundation

nonisolated final class LibUSBTransfer: @unchecked Sendable {
    enum Buffer {
        case input(capacity: Int)
        case output(Data)
    }

    private let context: LibUSBContext
    private let deviceHandle: OpaquePointer?
    private var handleOwner: LibUSBDeviceHandle?
    private let endpoint: UInt8
    private let bufferMode: Buffer
    private let timeoutMilliseconds: UInt32
    private let functions: LibUSBFunctionTable
    private let condition = NSCondition()
    private var transfer: UnsafeMutablePointer<libusb_transfer>?
    private var terminalResult: Result<Data, MTPCoreError>?
    private var submitted = false
    private var cancellationRequested = false
    private var started = false

    init(
        context: LibUSBContext,
        deviceHandle: OpaquePointer,
        endpoint: UInt8,
        buffer: Buffer,
        timeoutMilliseconds: UInt32,
        functions: LibUSBFunctionTable = LibUSBFunctionTable()
    ) {
        self.context = context
        self.deviceHandle = deviceHandle
        self.handleOwner = nil
        self.endpoint = endpoint
        self.bufferMode = buffer
        self.timeoutMilliseconds = timeoutMilliseconds
        self.functions = functions
    }

    init(
        handle: LibUSBDeviceHandle,
        endpoint: UInt8,
        buffer: Buffer,
        timeoutMilliseconds: UInt32,
        functions: LibUSBFunctionTable = LibUSBFunctionTable()
    ) {
        self.context = handle.context
        self.deviceHandle = nil
        self.handleOwner = handle
        self.endpoint = endpoint
        self.bufferMode = buffer
        self.timeoutMilliseconds = timeoutMilliseconds
        self.functions = functions
    }

    func execute(cancellation: MTPCancellationToken) throws -> Data {
        try condition.withLock {
            guard !started else {
                throw MTPCoreError.busy
            }
            started = true
        }
        try cancellation.throwIfCancelled()
        let leasedHandle: OpaquePointer
        let leasedOwner = handleOwner
        if let leasedOwner {
            leasedHandle = try leasedOwner.lease(self)
        } else if let deviceHandle {
            leasedHandle = deviceHandle
        } else {
            throw MTPCoreError.disconnected
        }
        defer {
            leasedOwner?.release(self)
            handleOwner = nil
        }
        try context.register(self)

        let bytes: Data
        let capacity: Int
        switch bufferMode {
        case .input(let requestedCapacity):
            guard requestedCapacity > 0, requestedCapacity <= Int(Int32.max) else {
                context.unregister(self)
                throw MTPCoreError.invalidInput("invalid libusb input buffer capacity")
            }
            bytes = Data()
            capacity = requestedCapacity
        case .output(let output):
            guard !output.isEmpty, output.count <= Int(Int32.max) else {
                context.unregister(self)
                throw MTPCoreError.invalidInput("invalid libusb output buffer size")
            }
            bytes = output
            capacity = output.count
        }

        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        if !bytes.isEmpty {
            bytes.copyBytes(to: buffer, count: bytes.count)
        }
        guard let transfer = functions.allocateTransfer(0) else {
            buffer.deallocate()
            context.unregister(self)
            throw MTPCoreError.usb(code: Int32(LIBUSB_ERROR_NO_MEM.rawValue))
        }
        self.transfer = transfer

        let callbackBox = LibUSBTransferCallbackBox(owner: self)
        let callbackReference = Unmanaged.passRetained(callbackBox)
        transfer.pointee.dev_handle = leasedHandle
        transfer.pointee.endpoint = endpoint
        transfer.pointee.type = UInt8(LIBUSB_TRANSFER_TYPE_BULK.rawValue)
        transfer.pointee.timeout = timeoutMilliseconds
        transfer.pointee.buffer = buffer
        transfer.pointee.length = Int32(capacity)
        transfer.pointee.actual_length = 0
        transfer.pointee.user_data = callbackReference.toOpaque()
        transfer.pointee.callback = libUSBTransferCompletionCallback

        defer {
            functions.freeTransfer(transfer)
            buffer.deallocate()
            self.transfer = nil
            context.unregister(self)
        }

        let submitResult = functions.submitTransfer(transfer)
        guard submitResult == 0 else {
            if let userData = transfer.pointee.user_data {
                transfer.pointee.user_data = nil
                Unmanaged<LibUSBTransferCallbackBox>
                    .fromOpaque(userData)
                    .release()
            }
            throw mtpErrorFromLibUSB(submitResult)
        }
        let cancelAfterSubmission = condition.withLock {
            submitted = true
            return cancellationRequested && terminalResult == nil
        }
        if cancelAfterSubmission {
            _ = functions.cancelTransfer(transfer)
        }

        cancellation.onCancel { [weak self] in
            self?.requestCancellation()
        }

        let result: Result<Data, MTPCoreError> = condition.withLock {
            while terminalResult == nil {
                condition.wait()
            }
            return terminalResult!
        }
        return try result.get()
    }

    func requestCancellationFromContext() {
        requestCancellation()
    }

    func requestCancellationFromHandle() {
        requestCancellation()
    }

    private func requestCancellation() {
        let transferToCancel: UnsafeMutablePointer<libusb_transfer>? = condition.withLock {
            guard terminalResult == nil, !cancellationRequested else {
                return nil
            }
            cancellationRequested = true
            return submitted ? transfer : nil
        }
        if let transferToCancel {
            _ = functions.cancelTransfer(transferToCancel)
        }
    }

    fileprivate func completed(_ transfer: UnsafeMutablePointer<libusb_transfer>) {
        let result: Result<Data, MTPCoreError>
        switch transfer.pointee.status {
        case LIBUSB_TRANSFER_COMPLETED:
            let count = max(0, min(Int(transfer.pointee.actual_length), Int(transfer.pointee.length)))
            if count == 0 {
                result = .success(Data())
            } else if let buffer = transfer.pointee.buffer {
                result = .success(Data(bytes: buffer, count: count))
            } else {
                result = .failure(.protocolViolation("libusb completed without a buffer"))
            }
        case LIBUSB_TRANSFER_TIMED_OUT:
            result = .failure(.timeout)
        case LIBUSB_TRANSFER_CANCELLED:
            result = .failure(.cancelled)
        case LIBUSB_TRANSFER_NO_DEVICE:
            result = .failure(.disconnected)
        case LIBUSB_TRANSFER_STALL:
            result = .failure(.usb(code: Int32(LIBUSB_ERROR_PIPE.rawValue)))
        case LIBUSB_TRANSFER_OVERFLOW:
            result = .failure(.usb(code: Int32(LIBUSB_ERROR_OVERFLOW.rawValue)))
        default:
            result = .failure(.usb(code: Int32(LIBUSB_ERROR_OTHER.rawValue)))
        }

        condition.withLock {
            guard terminalResult == nil else {
                return
            }
            terminalResult = result
            condition.broadcast()
        }
    }
}

private nonisolated final class LibUSBTransferCallbackBox {
    weak var owner: LibUSBTransfer?

    init(owner: LibUSBTransfer) {
        self.owner = owner
    }
}

private nonisolated let libUSBTransferCompletionCallback: libusb_transfer_cb_fn = {
    transfer in
    guard let transfer, let userData = transfer.pointee.user_data else {
        return
    }
    transfer.pointee.user_data = nil
    let callbackBox = Unmanaged<LibUSBTransferCallbackBox>
        .fromOpaque(userData)
        .takeRetainedValue()
    callbackBox.owner?.completed(transfer)
}

private extension NSCondition {
    nonisolated func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}
