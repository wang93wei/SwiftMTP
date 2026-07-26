import XCTest
@testable import SwiftMTP

final class MTPContainerTests: XCTestCase {
    func testInitialOperationAndResponseCodesMatchMTPWireValues() {
        XCTAssertEqual(MTPOperationCode.getDeviceInfo.rawValue, 0x1001)
        XCTAssertEqual(MTPOperationCode.openSession.rawValue, 0x1002)
        XCTAssertEqual(MTPOperationCode.closeSession.rawValue, 0x1003)
        XCTAssertEqual(MTPResponseCode.ok.rawValue, 0x2001)
    }

    func testCommandDataAndResponseEncodeExactHeaders() throws {
        let transaction = try MTPTransactionID(validating: 7)
        let command = MTPContainer(
            type: .command,
            code: 0x1001,
            transactionID: transaction,
            payload: Data([0x44, 0x33, 0x22, 0x11])
        )
        let data = MTPContainer(
            type: .data,
            code: 0x1009,
            transactionID: transaction,
            payload: Data([0xAA])
        )
        let response = MTPContainer(
            type: .response,
            code: 0x2001,
            transactionID: transaction,
            payload: Data()
        )

        XCTAssertEqual(
            try command.encoded(),
            Data([0x10, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x10, 0x07, 0x00, 0x00, 0x00,
                  0x44, 0x33, 0x22, 0x11])
        )
        XCTAssertEqual(
            try data.encoded(),
            Data([0x0D, 0x00, 0x00, 0x00, 0x02, 0x00, 0x09, 0x10, 0x07, 0x00, 0x00, 0x00, 0xAA])
        )
        XCTAssertEqual(
            try response.encoded(),
            Data([0x0C, 0x00, 0x00, 0x00, 0x03, 0x00, 0x01, 0x20, 0x07, 0x00, 0x00, 0x00])
        )
    }

    func testDataWireLengthCoversExactMaximumAndLargerSentinel() {
        XCTAssertEqual(MTPContainer.dataWireLength(payloadLength: 0xFFFF_FFF2), 0xFFFF_FFFE)
        XCTAssertEqual(MTPContainer.dataWireLength(payloadLength: 0xFFFF_FFF3), 0xFFFF_FFFF)
        XCTAssertEqual(MTPContainer.dataWireLength(payloadLength: 0xFFFF_FFF4), 0xFFFF_FFFF)
        XCTAssertEqual(MTPContainer.dataWireLength(payloadLength: 0xFFFF_FFFE), 0xFFFF_FFFF)
        XCTAssertEqual(MTPContainer.dataWireLength(payloadLength: 0xFFFF_FFFF), 0xFFFF_FFFF)
        XCTAssertEqual(MTPContainer.dataWireLength(payloadLength: 0x1_0000_0000), 0xFFFF_FFFF)
    }

    func testContainerRoundTripsMaximumTransactionID() throws {
        let container = MTPContainer(
            type: .command,
            code: MTPOperationCode.getDeviceInfo.rawValue,
            transactionID: try MTPTransactionID(validating: .max),
            payload: Data()
        )

        XCTAssertEqual(try MTPContainer.decode(container.encoded()), container)
    }

    func testDecodeRejectsInvalidLengthTypeAndTrailingBytes() throws {
        XCTAssertThrowsError(try MTPContainer.decode(Data([0x0B, 0, 0, 0, 1, 0, 1, 0x10, 0, 0, 0, 0])))
        XCTAssertThrowsError(try MTPContainer.decode(Data([0x0C, 0, 0, 0, 9, 0, 1, 0x10, 0, 0, 0, 0])))
        XCTAssertThrowsError(try MTPContainer.decode(Data([0x0C, 0, 0, 0, 1, 0, 1, 0x10, 0, 0, 0, 0, 0xAA])))
    }

    func testFramerWaitsForFragmentedHeaderAndPayload() throws {
        var framer = MTPContainerFramer()
        XCTAssertTrue(try framer.append(Data([0x0D, 0x00, 0x00])).isEmpty)
        XCTAssertTrue(try framer.append(Data([0x00, 0x02, 0x00, 0x09, 0x10])).isEmpty)
        let containers = try framer.append(Data([0x07, 0x00, 0x00, 0x00, 0xAA]))

        XCTAssertEqual(containers.count, 1)
        XCTAssertEqual(containers[0].payload, Data([0xAA]))
        XCTAssertEqual(framer.bufferedByteCount, 0)
    }
}
