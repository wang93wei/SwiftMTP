import CLibUSB
import Foundation

nonisolated final class LibUSBTransferCallbackBox {
    weak var owner: LibUSBTransfer?

    init(owner: LibUSBTransfer) {
        self.owner = owner
    }
}

nonisolated let libUSBTransferCompletionCallback: libusb_transfer_cb_fn = {
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

nonisolated func libUSBTerminalResult(
    for transfer: UnsafeMutablePointer<libusb_transfer>
) -> Result<Data, MTPCoreError> {
    switch transfer.pointee.status {
    case LIBUSB_TRANSFER_COMPLETED:
        return completedTransferResult(for: transfer)
    case LIBUSB_TRANSFER_TIMED_OUT:
        return .failure(.timeout)
    case LIBUSB_TRANSFER_CANCELLED:
        return .failure(.cancelled)
    case LIBUSB_TRANSFER_NO_DEVICE:
        return .failure(.disconnected)
    case LIBUSB_TRANSFER_STALL:
        return .failure(.usb(code: Int32(LIBUSB_ERROR_PIPE.rawValue)))
    case LIBUSB_TRANSFER_OVERFLOW:
        return .failure(.usb(code: Int32(LIBUSB_ERROR_OVERFLOW.rawValue)))
    default:
        return .failure(.usb(code: Int32(LIBUSB_ERROR_OTHER.rawValue)))
    }
}

private nonisolated func completedTransferResult(
    for transfer: UnsafeMutablePointer<libusb_transfer>
) -> Result<Data, MTPCoreError> {
    let count = max(
        0,
        min(Int(transfer.pointee.actual_length), Int(transfer.pointee.length))
    )
    guard count > 0 else {
        return .success(Data())
    }
    guard let buffer = transfer.pointee.buffer else {
        return .failure(
            .protocolViolation("libusb completed without a buffer")
        )
    }
    return .success(Data(bytes: buffer, count: count))
}
