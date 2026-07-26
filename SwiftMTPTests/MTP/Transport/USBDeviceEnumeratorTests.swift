import CLibUSB
import XCTest
@testable import SwiftMTP

final class USBDeviceEnumeratorTests: XCTestCase {
    func testEnumeratorMapsCDescriptorsRetainsOnlySupportedCandidates() throws {
        let fixture = USBEnumerationFixture()
        let context = try LibUSBContext(
            functions: fixture.functions,
            startsEventLoop: false
        )
        let enumerator = USBDeviceEnumerator(
            context: context,
            functions: fixture.functions
        )

        var candidates: [LibUSBDeviceCandidate]? = try enumerator.enumerate()

        XCTAssertEqual(candidates?.count, 1)
        XCTAssertEqual(candidates?.first?.interface.deviceID.rawValue, "swift:2:4.6:18d1:4ee7")
        XCTAssertEqual(candidates?.first?.interface.interfaceNumber, 3)
        XCTAssertEqual(candidates?.first?.interface.alternateSetting, 1)
        XCTAssertEqual(candidates?.first?.interface.bulkInEndpoint.address, 0x81)
        XCTAssertEqual(fixture.events.filter { $0 == "ref:1281" }.count, 1)
        XCTAssertEqual(fixture.events.filter { $0.hasPrefix("freeConfig:") }.count, 2)
        XCTAssertTrue(fixture.events.contains("freeDeviceList:1"))

        candidates = nil
        XCTAssertTrue(fixture.events.contains("unref:1281"))
        context.shutdown()
    }

    func testEnumeratorCleansListWhenDescriptorInspectionFails() throws {
        let fixture = USBEnumerationFixture()
        fixture.deviceDescriptorError = Int32(LIBUSB_ERROR_NO_DEVICE.rawValue)
        let context = try LibUSBContext(
            functions: fixture.functions,
            startsEventLoop: false
        )

        let candidates = try USBDeviceEnumerator(
            context: context,
            functions: fixture.functions
        ).enumerate()

        XCTAssertTrue(candidates.isEmpty)
        XCTAssertTrue(fixture.events.contains("freeDeviceList:1"))
        XCTAssertFalse(fixture.events.contains { $0.hasPrefix("ref:") })
        context.shutdown()
    }

    func testPortPathOverflowDoesNotCreateCollidingRootIdentity() throws {
        let fixture = USBEnumerationFixture()
        fixture.portNumbersResult = Int32(LIBUSB_ERROR_OVERFLOW.rawValue)
        let context = try LibUSBContext(
            functions: fixture.functions,
            startsEventLoop: false
        )

        let candidates = try USBDeviceEnumerator(
            context: context,
            functions: fixture.functions
        ).enumerate()

        XCTAssertTrue(candidates.isEmpty)
        XCTAssertFalse(fixture.events.contains { $0.hasPrefix("ref:") })
        XCTAssertTrue(fixture.events.contains("freeDeviceList:1"))
        context.shutdown()
    }
}

private final class USBEnumerationFixture: @unchecked Sendable {
    private let lock = NSLock()
    private let context = OpaquePointer(bitPattern: 0x100)!
    private let supported = OpaquePointer(bitPattern: 0x501)!
    private let unsupported = OpaquePointer(bitPattern: 0x502)!
    private var recordedEvents: [String] = []
    var deviceDescriptorError: Int32 = 0
    var portNumbersResult: Int32 = 2

    var events: [String] {
        lock.withLock { recordedEvents }
    }

    var functions: LibUSBFunctionTable {
        LibUSBFunctionTable(
            initialize: { [weak self] output in
                guard let self else { return Int32(LIBUSB_ERROR_OTHER.rawValue) }
                output.pointee = self.context
                return 0
            },
            exit: { _ in },
            getDeviceList: { [weak self] _, output in
                guard let self else { return Int(LIBUSB_ERROR_OTHER.rawValue) }
                let list = LibUSBDeviceListPointer.allocate(capacity: 3)
                list.initialize(repeating: nil, count: 3)
                list[0] = self.supported
                list[1] = self.unsupported
                output.pointee = list
                return 2
            },
            freeDeviceList: { [weak self] list, unref in
                self?.record("freeDeviceList:\(unref)")
                list?.deinitialize(count: 3)
                list?.deallocate()
            },
            refDevice: { [weak self] device in
                self?.record("ref:\(Int(bitPattern: device))")
                return device
            },
            unrefDevice: { [weak self] device in
                self?.record("unref:\(Int(bitPattern: device))")
            },
            getDeviceDescriptor: { [weak self] device, output in
                guard let self else { return Int32(LIBUSB_ERROR_OTHER.rawValue) }
                if self.deviceDescriptorError != 0 {
                    return self.deviceDescriptorError
                }
                var descriptor = libusb_device_descriptor()
                descriptor.idVendor = device == self.supported ? 0x18D1 : 0x9999
                descriptor.idProduct = device == self.supported ? 0x4EE7 : 0x0001
                descriptor.bNumConfigurations = 1
                output.pointee = descriptor
                return 0
            },
            getConfigDescriptor: { [weak self] device, _, output in
                guard let self else { return Int32(LIBUSB_ERROR_OTHER.rawValue) }
                output.pointee = self.makeConfiguration(
                    interfaceClass: device == self.supported ? 0x06 : 0x08
                )
                return 0
            },
            freeConfigDescriptor: { [weak self] descriptor in
                guard let descriptor else { return }
                self?.record("freeConfig:\(descriptor.pointee.bConfigurationValue)")
                Self.destroyConfiguration(descriptor)
            },
            getBusNumber: { _ in 2 },
            getPortNumbers: { _, output, _ in
                if self.portNumbersResult < 0 {
                    return self.portNumbersResult
                }
                output?[0] = 4
                output?[1] = 6
                return self.portNumbersResult
            }
        )
    }

    private func makeConfiguration(
        interfaceClass: UInt8
    ) -> UnsafeMutablePointer<libusb_config_descriptor> {
        let endpoints = UnsafeMutablePointer<libusb_endpoint_descriptor>.allocate(capacity: 3)
        endpoints.initialize(repeating: libusb_endpoint_descriptor(), count: 3)
        endpoints[0].bEndpointAddress = 0x81
        endpoints[0].bmAttributes = UInt8(LIBUSB_TRANSFER_TYPE_BULK.rawValue)
        endpoints[0].wMaxPacketSize = 512
        endpoints[1].bEndpointAddress = 0x02
        endpoints[1].bmAttributes = UInt8(LIBUSB_TRANSFER_TYPE_BULK.rawValue)
        endpoints[1].wMaxPacketSize = 512
        endpoints[2].bEndpointAddress = 0x83
        endpoints[2].bmAttributes = UInt8(LIBUSB_TRANSFER_TYPE_INTERRUPT.rawValue)
        endpoints[2].wMaxPacketSize = 64

        let alternate = UnsafeMutablePointer<libusb_interface_descriptor>.allocate(capacity: 1)
        alternate.initialize(to: libusb_interface_descriptor())
        alternate.pointee.bInterfaceNumber = 3
        alternate.pointee.bAlternateSetting = 1
        alternate.pointee.bNumEndpoints = 3
        alternate.pointee.bInterfaceClass = interfaceClass
        alternate.pointee.endpoint = UnsafePointer(endpoints)

        let interface = UnsafeMutablePointer<libusb_interface>.allocate(capacity: 1)
        interface.initialize(to: libusb_interface())
        interface.pointee.altsetting = UnsafePointer(alternate)
        interface.pointee.num_altsetting = 1

        let configuration = UnsafeMutablePointer<libusb_config_descriptor>.allocate(capacity: 1)
        configuration.initialize(to: libusb_config_descriptor())
        configuration.pointee.bConfigurationValue = 1
        configuration.pointee.bNumInterfaces = 1
        configuration.pointee.interface = UnsafePointer(interface)
        return configuration
    }

    private static func destroyConfiguration(
        _ configuration: UnsafeMutablePointer<libusb_config_descriptor>
    ) {
        if let interface = configuration.pointee.interface {
            if let alternate = interface.pointee.altsetting {
                if let endpoints = alternate.pointee.endpoint {
                    UnsafeMutablePointer(mutating: endpoints).deinitialize(count: 3)
                    UnsafeMutablePointer(mutating: endpoints).deallocate()
                }
                UnsafeMutablePointer(mutating: alternate).deinitialize(count: 1)
                UnsafeMutablePointer(mutating: alternate).deallocate()
            }
            UnsafeMutablePointer(mutating: interface).deinitialize(count: 1)
            UnsafeMutablePointer(mutating: interface).deallocate()
        }
        configuration.deinitialize(count: 1)
        configuration.deallocate()
    }

    private func record(_ event: String) {
        lock.withLock {
            recordedEvents.append(event)
        }
    }
}
