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
    private let addZeroPacket: Bool
    private let timeoutMilliseconds: UInt32
    private let functions: LibUSBFunctionTable
    private let state = LibUSBTransferState()

    init(
        context: LibUSBContext,
        deviceHandle: OpaquePointer,
        endpoint: UInt8,
        buffer: Buffer,
        addZeroPacket: Bool = false,
        timeoutMilliseconds: UInt32,
        functions: LibUSBFunctionTable = LibUSBFunctionTable()
    ) {
        self.context = context
        self.deviceHandle = deviceHandle
        self.handleOwner = nil
        self.endpoint = endpoint
        self.bufferMode = buffer
        self.addZeroPacket = addZeroPacket
        self.timeoutMilliseconds = timeoutMilliseconds
        self.functions = functions
    }

    init(
        handle: LibUSBDeviceHandle,
        endpoint: UInt8,
        buffer: Buffer,
        addZeroPacket: Bool = false,
        timeoutMilliseconds: UInt32,
        functions: LibUSBFunctionTable = LibUSBFunctionTable()
    ) {
        self.context = handle.context
        self.deviceHandle = nil
        self.handleOwner = handle
        self.endpoint = endpoint
        self.bufferMode = buffer
        self.addZeroPacket = addZeroPacket
        self.timeoutMilliseconds = timeoutMilliseconds
        self.functions = functions
    }

    func execute(cancellation: MTPCancellationToken) throws -> Data {
        try state.begin()
        try cancellation.throwIfCancelled()

        let leasedOwner = handleOwner
        let leasedHandle: OpaquePointer
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
        defer {
            context.unregister(self)
        }

        let resources = try LibUSBTransferResources(
            bufferMode: bufferMode,
            functions: functions
        )
        resources.configure(
            owner: self,
            deviceHandle: leasedHandle,
            endpoint: endpoint,
            addZeroPacket: addZeroPacket,
            timeoutMilliseconds: timeoutMilliseconds
        )
        state.install(resources.transfer)
        defer {
            state.discardTransfer()
            resources.release()
        }

        let submitResult = resources.submit()
        guard submitResult == 0 else {
            resources.releaseCallbackAfterSubmitFailure()
            throw mtpErrorFromLibUSB(submitResult)
        }
        cancelIfNeeded(state.markSubmitted())

        let cancellationRegistration = cancellation.onCancel { [weak self] in
            self?.requestCancellation()
        }
        defer {
            cancellationRegistration?.invalidate()
        }

        return try state.waitForTerminalResult().get()
    }

    func requestCancellationFromContext() {
        requestCancellation()
    }

    func requestCancellationFromHandle() {
        requestCancellation()
    }

    private func requestCancellation() {
        cancelIfNeeded(state.requestCancellation())
    }

    private func cancelIfNeeded(
        _ transferToCancel: UnsafeMutablePointer<libusb_transfer>?
    ) {
        if let transferToCancel {
            _ = functions.cancelTransfer(transferToCancel)
        }
    }

    func completed(_ transfer: UnsafeMutablePointer<libusb_transfer>) {
        state.complete(with: libUSBTerminalResult(for: transfer))
    }
}
