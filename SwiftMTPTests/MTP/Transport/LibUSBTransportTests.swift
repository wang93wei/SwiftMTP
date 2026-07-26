import CLibUSB
import XCTest
@testable import SwiftMTP

final class LibUSBTransportTests: XCTestCase {
    func testTransactionReassemblesSplitHeaderAndShortResponsePacket() throws {
        let fake = FakeLibUSBFunctions()
        let context = try LibUSBContext(functions: fake.table, startsEventLoop: false)
        let handle = try makeTestLibUSBDeviceHandle(context: context, functions: fake.table)
        let response = try MTPContainer(
            type: .response,
            code: MTPResponseCode.ok.rawValue,
            transactionID: try MTPTransactionID(validating: 7),
            payload: Data()
        ).encoded()
        fake.scriptedTransferBehaviors = [
            .immediate(status: LIBUSB_TRANSFER_COMPLETED, data: Data()),
            .immediate(status: LIBUSB_TRANSFER_COMPLETED, data: Data(response.prefix(5))),
            .immediate(status: LIBUSB_TRANSFER_COMPLETED, data: Data(response.dropFirst(5))),
        ]
        let transport = LibUSBTransport(
            handle: handle,
            functions: fake.table,
            readCapacity: 64
        )

        let fragments = try transport.transact(
            Data(repeating: 0xA5, count: 12),
            cancellation: MTPCancellationToken()
        )

        XCTAssertEqual(fragments, [Data(response.prefix(5)), Data(response.dropFirst(5))])
        handle.close()
        context.shutdown()
    }

    func testZeroLengthPacketDoesNotTerminateTransactionBeforeResponse() throws {
        let fake = FakeLibUSBFunctions()
        let context = try LibUSBContext(functions: fake.table, startsEventLoop: false)
        let handle = try makeTestLibUSBDeviceHandle(context: context, functions: fake.table)
        let response = try MTPContainer(
            type: .response,
            code: MTPResponseCode.ok.rawValue,
            transactionID: try MTPTransactionID(validating: 0),
            payload: Data()
        ).encoded()
        fake.scriptedTransferBehaviors = [
            .immediate(status: LIBUSB_TRANSFER_COMPLETED, data: Data()),
            .immediate(status: LIBUSB_TRANSFER_COMPLETED, data: Data()),
            .immediate(status: LIBUSB_TRANSFER_COMPLETED, data: response),
        ]
        let transport = LibUSBTransport(
            handle: handle,
            functions: fake.table,
            readCapacity: 64
        )

        let fragments = try transport.transact(
            Data(repeating: 0x5A, count: 12),
            cancellation: MTPCancellationToken()
        )

        XCTAssertEqual(fragments, [Data(), response])
        handle.close()
        context.shutdown()
    }

    func testShortCommandWriteFailsBeforeSubmittingRead() throws {
        let fake = FakeLibUSBFunctions()
        let context = try LibUSBContext(functions: fake.table, startsEventLoop: false)
        let handle = try makeTestLibUSBDeviceHandle(context: context, functions: fake.table)
        fake.scriptedTransferBehaviors = [
            .immediate(
                status: LIBUSB_TRANSFER_COMPLETED,
                data: Data(repeating: 0xA5, count: 8)
            ),
        ]
        let transport = LibUSBTransport(
            handle: handle,
            functions: fake.table,
            readCapacity: 64
        )

        XCTAssertThrowsError(
            try transport.transact(
                Data(repeating: 0x5A, count: 12),
                cancellation: MTPCancellationToken()
            )
        ) {
            guard case .protocolViolation = $0 as? MTPCoreError else {
                return XCTFail("expected protocol violation, got \($0)")
            }
        }
        XCTAssertEqual(fake.events.filter { $0 == "submitTransfer" }.count, 1)
        handle.close()
        context.shutdown()
    }

}
