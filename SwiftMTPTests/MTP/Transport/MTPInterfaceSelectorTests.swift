import XCTest
@testable import SwiftMTP

final class MTPInterfaceSelectorTests: XCTestCase {
    func testSelectsRequiredEndpointsAcrossAlternateSettings() throws {
        let unsupported = USBAlternateSettingDescriptor(
            interfaceNumber: 1,
            alternateSetting: 0,
            interfaceClass: 0x08,
            interfaceSubclass: 0x06,
            interfaceProtocol: 0x50,
            endpoints: []
        )
        let mtp = USBAlternateSettingDescriptor(
            interfaceNumber: 3,
            alternateSetting: 1,
            interfaceClass: 0x06,
            interfaceSubclass: 0x01,
            interfaceProtocol: 0x01,
            endpoints: [
                .init(address: 0x81, transferType: .bulk, maxPacketSize: 512),
                .init(address: 0x02, transferType: .bulk, maxPacketSize: 512),
                .init(address: 0x83, transferType: .interrupt, maxPacketSize: 64),
            ]
        )
        let descriptor = USBDeviceDescriptorSnapshot(
            busNumber: 5,
            portPath: [2, 4],
            vendorID: 0x18D1,
            productID: 0x4EE1,
            configurations: [
                .init(value: 1, interfaces: [[unsupported], [mtp]]),
            ]
        )

        let candidate = try XCTUnwrap(MTPInterfaceSelector.select(from: descriptor))

        XCTAssertEqual(candidate.deviceID.rawValue, "swift:5:2.4:18d1:4ee1")
        XCTAssertEqual(candidate.configurationValue, 1)
        XCTAssertEqual(candidate.interfaceNumber, 3)
        XCTAssertEqual(candidate.alternateSetting, 1)
        XCTAssertEqual(candidate.bulkInEndpoint.address, 0x81)
        XCTAssertEqual(candidate.bulkOutEndpoint.address, 0x02)
        XCTAssertEqual(candidate.interruptInEndpoint.address, 0x83)
    }

    func testRejectsUnsupportedOrAmbiguousEndpointShapes() {
        let missingInterrupt = USBAlternateSettingDescriptor(
            interfaceNumber: 1,
            alternateSetting: 0,
            interfaceClass: 0x06,
            interfaceSubclass: 0x01,
            interfaceProtocol: 0x01,
            endpoints: [
                .init(address: 0x81, transferType: .bulk, maxPacketSize: 512),
                .init(address: 0x02, transferType: .bulk, maxPacketSize: 512),
            ]
        )
        let extraEndpoint = USBAlternateSettingDescriptor(
            interfaceNumber: 2,
            alternateSetting: 0,
            interfaceClass: 0x06,
            interfaceSubclass: 0x01,
            interfaceProtocol: 0x01,
            endpoints: [
                .init(address: 0x81, transferType: .bulk, maxPacketSize: 512),
                .init(address: 0x02, transferType: .bulk, maxPacketSize: 512),
                .init(address: 0x83, transferType: .interrupt, maxPacketSize: 64),
                .init(address: 0x84, transferType: .interrupt, maxPacketSize: 64),
            ]
        )

        for alternate in [missingInterrupt, extraEndpoint] {
            let descriptor = USBDeviceDescriptorSnapshot(
                busNumber: 1,
                portPath: [1],
                vendorID: 1,
                productID: 2,
                configurations: [.init(value: 1, interfaces: [[alternate]])]
            )
            XCTAssertNil(MTPInterfaceSelector.select(from: descriptor))
        }
    }
}
