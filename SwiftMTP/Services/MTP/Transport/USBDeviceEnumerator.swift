import CLibUSB
import Foundation
import OSLog

/// Enumerates libusb devices and retains only candidates whose descriptors
/// expose one complete MTP/PTP endpoint set.
nonisolated final class USBDeviceEnumerator {
    private let context: LibUSBContext
    private let functions: LibUSBFunctionTable

    init(
        context: LibUSBContext,
        functions: LibUSBFunctionTable = LibUSBFunctionTable()
    ) {
        self.context = context
        self.functions = functions
    }

    func enumerate() throws -> [LibUSBDeviceCandidate] {
        let rawContext = try context.rawContextForEnumeration()
        var list: LibUSBDeviceListPointer?
        let count = functions.getDeviceList(rawContext, &list)
        guard count >= 0 else {
            throw mtpErrorFromLibUSB(Int32(count))
        }
        guard let list else {
            return []
        }
        defer { functions.freeDeviceList(list, 1) }

        var candidates: [LibUSBDeviceCandidate] = []
        for index in 0..<count {
            guard let rawDevice = list[index] else {
                continue
            }
            do {
                let descriptor = try descriptorSnapshot(for: rawDevice)
                guard let mtpInterface = MTPInterfaceSelector.select(from: descriptor) else {
                    MTPLog.usb.debug("Ignoring unsupported USB interface")
                    continue
                }
                guard let retained = functions.refDevice(rawDevice) else {
                    throw MTPCoreError.usb(code: Int32(LIBUSB_ERROR_NO_MEM.rawValue))
                }
                candidates.append(
                    LibUSBDeviceCandidate(
                        rawDevice: retained,
                        interface: mtpInterface,
                        functions: functions,
                        ownsReference: true
                    )
                )
            } catch {
                MTPLog.usb.error(
                    "USB descriptor inspection failed: \(String(describing: error), privacy: .public)"
                )
            }
        }
        return candidates
    }

    private func descriptorSnapshot(
        for rawDevice: OpaquePointer
    ) throws -> USBDeviceDescriptorSnapshot {
        var descriptor = libusb_device_descriptor()
        let descriptorResult = functions.getDeviceDescriptor(rawDevice, &descriptor)
        guard descriptorResult == 0 else {
            throw mtpErrorFromLibUSB(descriptorResult)
        }

        var portPath = [UInt8](repeating: 0, count: 8)
        let portCount = portPath.withUnsafeMutableBufferPointer {
            functions.getPortNumbers(rawDevice, $0.baseAddress, Int32($0.count))
        }
        if portCount < 0 {
            throw mtpErrorFromLibUSB(portCount)
        }
        if portCount <= 0 {
            portPath.removeAll()
        } else {
            portPath.removeSubrange(Int(portCount)..<portPath.count)
        }

        var configurations: [USBConfigurationDescriptorSnapshot] = []
        for configurationIndex in 0..<descriptor.bNumConfigurations {
            var rawConfiguration: LibUSBConfigDescriptorPointer?
            let result = functions.getConfigDescriptor(
                rawDevice,
                configurationIndex,
                &rawConfiguration
            )
            guard result == 0, let rawConfiguration else {
                MTPLog.usb.debug(
                    "Skipping unreadable USB configuration \(configurationIndex, privacy: .public)"
                )
                continue
            }
            defer { functions.freeConfigDescriptor(rawConfiguration) }
            configurations.append(Self.map(rawConfiguration.pointee))
        }

        return USBDeviceDescriptorSnapshot(
            busNumber: functions.getBusNumber(rawDevice),
            portPath: portPath,
            vendorID: descriptor.idVendor,
            productID: descriptor.idProduct,
            configurations: configurations
        )
    }

    static func map(
        _ descriptor: libusb_config_descriptor
    ) -> USBConfigurationDescriptorSnapshot {
        var interfaces: [[USBAlternateSettingDescriptor]] = []
        if let interfacePointer = descriptor.interface {
            for interfaceIndex in 0..<Int(descriptor.bNumInterfaces) {
                let rawInterface = interfacePointer[interfaceIndex]
                var alternateSettings: [USBAlternateSettingDescriptor] = []
                if let alternatePointer = rawInterface.altsetting {
                    for alternateIndex in 0..<Int(rawInterface.num_altsetting) {
                        let alternate = alternatePointer[alternateIndex]
                        var endpoints: [USBEndpointDescriptor] = []
                        if let endpointPointer = alternate.endpoint {
                            for endpointIndex in 0..<Int(alternate.bNumEndpoints) {
                                let endpoint = endpointPointer[endpointIndex]
                                guard let transferType = USBTransferType(
                                    rawValue: endpoint.bmAttributes & 0x03
                                ) else {
                                    continue
                                }
                                endpoints.append(
                                    USBEndpointDescriptor(
                                        address: endpoint.bEndpointAddress,
                                        transferType: transferType,
                                        maxPacketSize: endpoint.wMaxPacketSize
                                    )
                                )
                            }
                        }
                        alternateSettings.append(
                            USBAlternateSettingDescriptor(
                                interfaceNumber: alternate.bInterfaceNumber,
                                alternateSetting: alternate.bAlternateSetting,
                                interfaceClass: alternate.bInterfaceClass,
                                interfaceSubclass: alternate.bInterfaceSubClass,
                                interfaceProtocol: alternate.bInterfaceProtocol,
                                endpoints: endpoints
                            )
                        )
                    }
                }
                interfaces.append(alternateSettings)
            }
        }
        return USBConfigurationDescriptorSnapshot(
            value: descriptor.bConfigurationValue,
            interfaces: interfaces
        )
    }
}
