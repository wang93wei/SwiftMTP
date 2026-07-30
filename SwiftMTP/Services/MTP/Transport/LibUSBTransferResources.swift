import CLibUSB
import Foundation

/// Owns the C transfer and buffer from allocation through terminal cleanup.
nonisolated final class LibUSBTransferResources {
    let transfer: UnsafeMutablePointer<libusb_transfer>

    private let buffer: UnsafeMutablePointer<UInt8>
    private let capacity: Int
    private let functions: LibUSBFunctionTable

    init(
        bufferMode: LibUSBTransfer.Buffer,
        functions: LibUSBFunctionTable
    ) throws {
        let specification = try Self.bufferSpecification(for: bufferMode)
        capacity = specification.capacity
        self.functions = functions
        buffer = .allocate(capacity: specification.capacity)
        if !specification.bytes.isEmpty {
            specification.bytes.copyBytes(
                to: buffer,
                count: specification.bytes.count
            )
        }
        guard let transfer = functions.allocateTransfer(0) else {
            buffer.deallocate()
            throw MTPCoreError.usb(code: Int32(LIBUSB_ERROR_NO_MEM.rawValue))
        }
        self.transfer = transfer
    }

    func configure(
        owner: LibUSBTransfer,
        deviceHandle: OpaquePointer,
        endpoint: UInt8,
        addZeroPacket: Bool,
        timeoutMilliseconds: UInt32
    ) {
        let callbackBox = LibUSBTransferCallbackBox(owner: owner)
        let callbackReference = Unmanaged.passRetained(callbackBox)
        transfer.pointee.dev_handle = deviceHandle
        transfer.pointee.endpoint = endpoint
        transfer.pointee.type = UInt8(LIBUSB_TRANSFER_TYPE_BULK.rawValue)
        transfer.pointee.flags = addZeroPacket
            ? UInt8(LIBUSB_TRANSFER_ADD_ZERO_PACKET.rawValue)
            : 0
        transfer.pointee.timeout = timeoutMilliseconds
        transfer.pointee.buffer = buffer
        transfer.pointee.length = Int32(capacity)
        transfer.pointee.actual_length = 0
        transfer.pointee.user_data = callbackReference.toOpaque()
        transfer.pointee.callback = libUSBTransferCompletionCallback
    }

    func submit() -> Int32 {
        functions.submitTransfer(transfer)
    }

    func releaseCallbackAfterSubmitFailure() {
        guard let userData = transfer.pointee.user_data else {
            return
        }
        transfer.pointee.user_data = nil
        Unmanaged<LibUSBTransferCallbackBox>
            .fromOpaque(userData)
            .release()
    }

    /// Call only after submit failure or the terminal callback.
    func release() {
        functions.freeTransfer(transfer)
        buffer.deallocate()
    }

    private static func bufferSpecification(
        for bufferMode: LibUSBTransfer.Buffer
    ) throws -> (bytes: Data, capacity: Int) {
        switch bufferMode {
        case .input(let capacity):
            guard capacity > 0, capacity <= Int(Int32.max) else {
                throw MTPCoreError.invalidInput(
                    "invalid libusb input buffer capacity"
                )
            }
            return (Data(), capacity)
        case .output(let bytes):
            guard !bytes.isEmpty, bytes.count <= Int(Int32.max) else {
                throw MTPCoreError.invalidInput(
                    "invalid libusb output buffer size"
                )
            }
            return (bytes, bytes.count)
        }
    }

}
