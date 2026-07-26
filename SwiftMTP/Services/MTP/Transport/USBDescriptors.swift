import Foundation

nonisolated enum USBTransferType: UInt8, Equatable, Sendable {
    case control = 0
    case isochronous = 1
    case bulk = 2
    case interrupt = 3
}

nonisolated struct USBEndpointDescriptor: Equatable, Sendable {
    let address: UInt8
    let transferType: USBTransferType
    let maxPacketSize: UInt16

    var isInput: Bool {
        address & 0x80 != 0
    }
}

nonisolated struct USBAlternateSettingDescriptor: Equatable, Sendable {
    let interfaceNumber: UInt8
    let alternateSetting: UInt8
    let interfaceClass: UInt8
    let interfaceSubclass: UInt8
    let interfaceProtocol: UInt8
    let endpoints: [USBEndpointDescriptor]
}

nonisolated struct USBConfigurationDescriptorSnapshot: Equatable, Sendable {
    let value: UInt8
    let interfaces: [[USBAlternateSettingDescriptor]]
}

nonisolated struct USBDeviceDescriptorSnapshot: Equatable, Sendable {
    let busNumber: UInt8
    let portPath: [UInt8]
    let vendorID: UInt16
    let productID: UInt16
    let configurations: [USBConfigurationDescriptorSnapshot]
}

nonisolated struct MTPUSBInterface: Equatable, Sendable {
    let deviceID: MTPDeviceID
    let configurationValue: UInt8
    let interfaceNumber: UInt8
    let alternateSetting: UInt8
    let bulkInEndpoint: USBEndpointDescriptor
    let bulkOutEndpoint: USBEndpointDescriptor
    let interruptInEndpoint: USBEndpointDescriptor
}

nonisolated enum MTPInterfaceSelector {
    static func select(from descriptor: USBDeviceDescriptorSnapshot) -> MTPUSBInterface? {
        for configuration in descriptor.configurations {
            for interface in configuration.interfaces {
                for alternate in interface {
                    guard isMTPCompatibleClass(alternate), alternate.endpoints.count == 3 else {
                        continue
                    }
                    let bulkIn = alternate.endpoints.filter {
                        $0.transferType == .bulk && $0.isInput
                    }
                    let bulkOut = alternate.endpoints.filter {
                        $0.transferType == .bulk && !$0.isInput
                    }
                    let interruptIn = alternate.endpoints.filter {
                        $0.transferType == .interrupt && $0.isInput
                    }
                    guard bulkIn.count == 1, bulkOut.count == 1, interruptIn.count == 1 else {
                        continue
                    }
                    guard let deviceID = try? MTPDeviceID(validating: stableID(for: descriptor)) else {
                        return nil
                    }
                    return MTPUSBInterface(
                        deviceID: deviceID,
                        configurationValue: configuration.value,
                        interfaceNumber: alternate.interfaceNumber,
                        alternateSetting: alternate.alternateSetting,
                        bulkInEndpoint: bulkIn[0],
                        bulkOutEndpoint: bulkOut[0],
                        interruptInEndpoint: interruptIn[0]
                    )
                }
            }
        }
        return nil
    }

    private static func isMTPCompatibleClass(
        _ descriptor: USBAlternateSettingDescriptor
    ) -> Bool {
        // PTP/MTP normally uses the Still Image class. A small number of
        // Android vendors expose the same endpoint contract as vendor-specific.
        descriptor.interfaceClass == 0x06 || descriptor.interfaceClass == 0xFF
    }

    private static func stableID(for descriptor: USBDeviceDescriptorSnapshot) -> String {
        let ports = descriptor.portPath.isEmpty
            ? "root"
            : descriptor.portPath.map(String.init).joined(separator: ".")
        return String(
            format: "swift:%u:%@:%04x:%04x",
            descriptor.busNumber,
            ports,
            descriptor.vendorID,
            descriptor.productID
        )
    }
}
