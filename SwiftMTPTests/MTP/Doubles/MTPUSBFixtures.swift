import Foundation
@testable import SwiftMTP

func makeTestLibUSBDeviceCandidate(
    deviceID: MTPDeviceID,
    rawDeviceValue: Int = 0x300,
    alternateSetting: UInt8 = 0,
    functions: LibUSBFunctionTable
) -> LibUSBDeviceCandidate {
    LibUSBDeviceCandidate(
        rawDevice: OpaquePointer(bitPattern: rawDeviceValue)!,
        interface: MTPUSBInterface(
            deviceID: deviceID,
            configurationValue: 1,
            interfaceNumber: 3,
            alternateSetting: alternateSetting,
            bulkInEndpoint: .init(
                address: 0x81,
                transferType: .bulk,
                maxPacketSize: 512
            ),
            bulkOutEndpoint: .init(
                address: 0x02,
                transferType: .bulk,
                maxPacketSize: 512
            ),
            interruptInEndpoint: .init(
                address: 0x83,
                transferType: .interrupt,
                maxPacketSize: 64
            )
        ),
        functions: functions,
        ownsReference: false
    )
}

func makeTestLibUSBDeviceHandle(
    context: LibUSBContext,
    functions: LibUSBFunctionTable
) throws -> LibUSBDeviceHandle {
    let candidate = makeTestLibUSBDeviceCandidate(
        deviceID: try MTPDeviceID(validating: "swift:1:1:0001:0002"),
        functions: functions
    )
    return try LibUSBDeviceHandle(
        context: context,
        candidate: candidate,
        functions: functions
    )
}
