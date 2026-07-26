import CLibUSB
import Foundation

typealias LibUSBDeviceListPointer = UnsafeMutablePointer<OpaquePointer?>
typealias LibUSBConfigDescriptorPointer =
    UnsafeMutablePointer<libusb_config_descriptor>

/// Injectable C boundary. The live table forwards directly to libusb; tests
/// replace only the calls whose ordering or result they need to control.
nonisolated struct LibUSBFunctionTable: @unchecked Sendable {
    let initialize: (UnsafeMutablePointer<OpaquePointer?>) -> Int32
    let exit: (OpaquePointer?) -> Void
    let getDeviceList: (
        OpaquePointer?,
        UnsafeMutablePointer<LibUSBDeviceListPointer?>
    ) -> Int
    let freeDeviceList: (LibUSBDeviceListPointer?, Int32) -> Void
    let refDevice: (OpaquePointer?) -> OpaquePointer?
    let unrefDevice: (OpaquePointer?) -> Void
    let getDeviceDescriptor: (
        OpaquePointer?,
        UnsafeMutablePointer<libusb_device_descriptor>
    ) -> Int32
    let getConfigDescriptor: (
        OpaquePointer?,
        UInt8,
        UnsafeMutablePointer<LibUSBConfigDescriptorPointer?>
    ) -> Int32
    let freeConfigDescriptor: (LibUSBConfigDescriptorPointer?) -> Void
    let getBusNumber: (OpaquePointer?) -> UInt8
    let getPortNumbers: (OpaquePointer?, UnsafeMutablePointer<UInt8>?, Int32) -> Int32
    let open: (OpaquePointer?, UnsafeMutablePointer<OpaquePointer?>) -> Int32
    let close: (OpaquePointer?) -> Void
    let getConfiguration: (OpaquePointer?, UnsafeMutablePointer<Int32>) -> Int32
    let setConfiguration: (OpaquePointer?, Int32) -> Int32
    let claimInterface: (OpaquePointer?, Int32) -> Int32
    let setInterfaceAltSetting: (OpaquePointer?, Int32, Int32) -> Int32
    let releaseInterface: (OpaquePointer?, Int32) -> Int32
    let allocateTransfer: (Int32) -> UnsafeMutablePointer<libusb_transfer>?
    let submitTransfer: (UnsafeMutablePointer<libusb_transfer>?) -> Int32
    let cancelTransfer: (UnsafeMutablePointer<libusb_transfer>?) -> Int32
    let freeTransfer: (UnsafeMutablePointer<libusb_transfer>?) -> Void
    let handleEventsTimeoutCompleted: (
        OpaquePointer?,
        UnsafeMutablePointer<timeval>?,
        UnsafeMutablePointer<Int32>?
    ) -> Int32

    init(
        initialize: @escaping (UnsafeMutablePointer<OpaquePointer?>) -> Int32 = {
            libusb_init($0)
        },
        exit: @escaping (OpaquePointer?) -> Void = {
            libusb_exit($0)
        },
        getDeviceList: @escaping (
            OpaquePointer?,
            UnsafeMutablePointer<LibUSBDeviceListPointer?>
        ) -> Int = {
            libusb_get_device_list($0, $1)
        },
        freeDeviceList: @escaping (LibUSBDeviceListPointer?, Int32) -> Void = {
            libusb_free_device_list($0, $1)
        },
        refDevice: @escaping (OpaquePointer?) -> OpaquePointer? = {
            libusb_ref_device($0)
        },
        unrefDevice: @escaping (OpaquePointer?) -> Void = {
            libusb_unref_device($0)
        },
        getDeviceDescriptor: @escaping (
            OpaquePointer?,
            UnsafeMutablePointer<libusb_device_descriptor>
        ) -> Int32 = {
            libusb_get_device_descriptor($0, $1)
        },
        getConfigDescriptor: @escaping (
            OpaquePointer?,
            UInt8,
            UnsafeMutablePointer<LibUSBConfigDescriptorPointer?>
        ) -> Int32 = {
            libusb_get_config_descriptor($0, $1, $2)
        },
        freeConfigDescriptor: @escaping (LibUSBConfigDescriptorPointer?) -> Void = {
            libusb_free_config_descriptor($0)
        },
        getBusNumber: @escaping (OpaquePointer?) -> UInt8 = {
            libusb_get_bus_number($0)
        },
        getPortNumbers: @escaping (
            OpaquePointer?,
            UnsafeMutablePointer<UInt8>?,
            Int32
        ) -> Int32 = {
            libusb_get_port_numbers($0, $1, $2)
        },
        open: @escaping (OpaquePointer?, UnsafeMutablePointer<OpaquePointer?>) -> Int32 = {
            libusb_open($0, $1)
        },
        close: @escaping (OpaquePointer?) -> Void = {
            libusb_close($0)
        },
        getConfiguration: @escaping (
            OpaquePointer?,
            UnsafeMutablePointer<Int32>
        ) -> Int32 = {
            libusb_get_configuration($0, $1)
        },
        setConfiguration: @escaping (OpaquePointer?, Int32) -> Int32 = {
            libusb_set_configuration($0, $1)
        },
        claimInterface: @escaping (OpaquePointer?, Int32) -> Int32 = {
            libusb_claim_interface($0, $1)
        },
        setInterfaceAltSetting: @escaping (OpaquePointer?, Int32, Int32) -> Int32 = {
            libusb_set_interface_alt_setting($0, $1, $2)
        },
        releaseInterface: @escaping (OpaquePointer?, Int32) -> Int32 = {
            libusb_release_interface($0, $1)
        },
        allocateTransfer: @escaping (Int32) -> UnsafeMutablePointer<libusb_transfer>? = {
            libusb_alloc_transfer($0)
        },
        submitTransfer: @escaping (UnsafeMutablePointer<libusb_transfer>?) -> Int32 = {
            libusb_submit_transfer($0)
        },
        cancelTransfer: @escaping (UnsafeMutablePointer<libusb_transfer>?) -> Int32 = {
            libusb_cancel_transfer($0)
        },
        freeTransfer: @escaping (UnsafeMutablePointer<libusb_transfer>?) -> Void = {
            libusb_free_transfer($0)
        },
        handleEventsTimeoutCompleted: @escaping (
            OpaquePointer?,
            UnsafeMutablePointer<timeval>?,
            UnsafeMutablePointer<Int32>?
        ) -> Int32 = {
            libusb_handle_events_timeout_completed($0, $1, $2)
        }
    ) {
        self.initialize = initialize
        self.exit = exit
        self.getDeviceList = getDeviceList
        self.freeDeviceList = freeDeviceList
        self.refDevice = refDevice
        self.unrefDevice = unrefDevice
        self.getDeviceDescriptor = getDeviceDescriptor
        self.getConfigDescriptor = getConfigDescriptor
        self.freeConfigDescriptor = freeConfigDescriptor
        self.getBusNumber = getBusNumber
        self.getPortNumbers = getPortNumbers
        self.open = open
        self.close = close
        self.getConfiguration = getConfiguration
        self.setConfiguration = setConfiguration
        self.claimInterface = claimInterface
        self.setInterfaceAltSetting = setInterfaceAltSetting
        self.releaseInterface = releaseInterface
        self.allocateTransfer = allocateTransfer
        self.submitTransfer = submitTransfer
        self.cancelTransfer = cancelTransfer
        self.freeTransfer = freeTransfer
        self.handleEventsTimeoutCompleted = handleEventsTimeoutCompleted
    }
}

nonisolated func mtpErrorFromLibUSB(_ code: Int32) -> MTPCoreError {
    switch code {
    case Int32(LIBUSB_ERROR_ACCESS.rawValue):
        .permissionDenied
    case Int32(LIBUSB_ERROR_BUSY.rawValue):
        .busy
    case Int32(LIBUSB_ERROR_NO_DEVICE.rawValue):
        .disconnected
    case Int32(LIBUSB_ERROR_TIMEOUT.rawValue):
        .timeout
    default:
        .usb(code: code)
    }
}
