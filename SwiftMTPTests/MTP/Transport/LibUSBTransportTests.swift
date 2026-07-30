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

    func testShortOutboundMetadataWriteFailsBeforeSubmittingRead() throws {
        let fake = FakeLibUSBFunctions()
        let context = try LibUSBContext(functions: fake.table, startsEventLoop: false)
        let handle = try makeTestLibUSBDeviceHandle(context: context, functions: fake.table)
        fake.scriptedTransferBehaviors = [
            .immediate(
                status: LIBUSB_TRANSFER_COMPLETED,
                data: Data(repeating: 0x5A, count: 12)
            ),
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
                outboundData: Data(repeating: 0xA5, count: 12),
                cancellation: MTPCancellationToken()
            )
        ) {
            guard case .protocolViolation = $0 as? MTPCoreError else {
                return XCTFail("expected protocol violation, got \($0)")
            }
        }
        XCTAssertEqual(fake.events.filter { $0 == "submitTransfer" }.count, 2)
        handle.close()
        context.shutdown()
    }

    func testStreamingInboundWritesSequentialChunksAndReturnsTypedResponse() throws {
        let fake = FakeLibUSBFunctions()
        let context = try LibUSBContext(functions: fake.table, startsEventLoop: false)
        let handle = try makeTestLibUSBDeviceHandle(context: context, functions: fake.table)
        let transactionID = try MTPTransactionID(validating: 21)
        let header = MTPStreamingDataHeader(
            operationCode: .getObject,
            transactionID: transactionID,
            payloadLength: 4
        )
        var responsePayload = MTPBinaryWriter()
        responsePayload.write(UInt32(0x1122_3344))
        let response = try MTPContainer(
            type: .response,
            code: MTPResponseCode.ok.rawValue,
            transactionID: transactionID,
            payload: responsePayload.data
        ).encoded()
        fake.scriptedTransferBehaviors = [
            .immediate(status: LIBUSB_TRANSFER_COMPLETED, data: Data()),
            .immediate(status: LIBUSB_TRANSFER_COMPLETED, data: Data(header.encoded().prefix(5))),
            .immediate(
                status: LIBUSB_TRANSFER_COMPLETED,
                data: Data(header.encoded().dropFirst(5)) + Data([1, 2])
            ),
            .immediate(status: LIBUSB_TRANSFER_COMPLETED, data: Data([3, 4])),
            .immediate(status: LIBUSB_TRANSFER_COMPLETED, data: response),
        ]
        let transport = LibUSBTransport(handle: handle, functions: fake.table, readCapacity: 64)
        let sink = RecordingMTPStreamSink()

        let result = try transport.receive(
            Data(repeating: 0xA5, count: 12),
            operationCode: .getObject,
            transactionID: transactionID,
            expectedPayloadLength: 4,
            sink: sink,
            cancellation: MTPCancellationToken()
        )

        XCTAssertEqual(sink.chunks, [Data([1, 2]), Data([3, 4])])
        XCTAssertEqual(result.transferredByteCount, 4)
        XCTAssertEqual(result.responseCode, .ok)
        XCTAssertEqual(result.responseParameters, [0x1122_3344])
        handle.close()
        context.shutdown()
    }

    func testStreamingOutboundSubmitsNextChunkOnlyAfterPreviousTerminalCallback() throws {
        let fake = FakeLibUSBFunctions()
        let context = try LibUSBContext(functions: fake.table, startsEventLoop: false)
        let handle = try makeTestLibUSBDeviceHandle(context: context, functions: fake.table)
        let transactionID = try MTPTransactionID(validating: 22)
        let response = try MTPContainer(
            type: .response,
            code: MTPResponseCode.ok.rawValue,
            transactionID: transactionID,
            payload: Data()
        ).encoded()
        fake.scriptedTransferBehaviors = [
            .immediate(status: LIBUSB_TRANSFER_COMPLETED, data: Data()),
            .deferred,
            .immediate(status: LIBUSB_TRANSFER_COMPLETED, data: Data()),
            .immediate(status: LIBUSB_TRANSFER_COMPLETED, data: response),
        ]
        let transport = LibUSBTransport(handle: handle, functions: fake.table, readCapacity: 64)
        let source = ArrayMTPStreamSource(chunks: [Data([1, 2]), Data([3, 4])], length: 4)
        let token = MTPCancellationToken()
        let result = UncheckedResultBox<Result<MTPStreamingTransactionResult, Error>>()
        let finished = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            result.store(Result {
                try transport.send(
                    Data(repeating: 0xA5, count: 12),
                    dataHeader: MTPStreamingDataHeader(
                        operationCode: .sendObject,
                        transactionID: transactionID,
                        payloadLength: 4
                    ),
                    source: source,
                    cancellation: token
                )
            })
            finished.signal()
        }

        XCTAssertTrue(fake.waitForPendingTransferCount(1))
        XCTAssertEqual(fake.events.filter { $0 == "submitTransfer" }.count, 2)
        fake.completeNext()
        XCTAssertEqual(finished.wait(timeout: .now() + 1), .success)
        XCTAssertEqual(try result.value?.get().transferredByteCount, 4)
        XCTAssertEqual(fake.maximumPendingTransferCount, 1)
        handle.close()
        context.shutdown()
    }

    func testUnknownStreamingOutboundMarksFinalChunkForZeroLengthPacket() throws {
        let fake = FakeLibUSBFunctions()
        let context = try LibUSBContext(functions: fake.table, startsEventLoop: false)
        let handle = try makeTestLibUSBDeviceHandle(context: context, functions: fake.table)
        let transactionID = try MTPTransactionID(validating: 26)
        let response = try MTPContainer(
            type: .response,
            code: MTPResponseCode.ok.rawValue,
            transactionID: transactionID,
            payload: Data()
        ).encoded()
        fake.scriptedTransferBehaviors = [
            .immediate(status: LIBUSB_TRANSFER_COMPLETED, data: Data()),
            .immediate(status: LIBUSB_TRANSFER_COMPLETED, data: Data()),
            .immediate(status: LIBUSB_TRANSFER_COMPLETED, data: Data()),
            .immediate(status: LIBUSB_TRANSFER_COMPLETED, data: response),
        ]
        let transport = LibUSBTransport(handle: handle, functions: fake.table, readCapacity: 64)
        let source = ArrayMTPStreamSource(chunks: [Data([1, 2])], length: nil)

        _ = try transport.send(
            Data(repeating: 0xA5, count: 12),
            dataHeader: MTPStreamingDataHeader(
                operationCode: .sendObject,
                transactionID: transactionID,
                payloadLength: nil
            ),
            source: source,
            cancellation: MTPCancellationToken()
        )

        XCTAssertEqual(
            fake.submittedTransferFlags.prefix(3),
            [0, 0, UInt8(LIBUSB_TRANSFER_ADD_ZERO_PACKET.rawValue)]
        )
        handle.close()
        context.shutdown()
    }

    func testKnownLengthStreamingOutboundStartsWithOneEndpointPacket() throws {
        let fake = FakeLibUSBFunctions()
        let context = try LibUSBContext(functions: fake.table, startsEventLoop: false)
        let handle = try makeTestLibUSBDeviceHandle(context: context, functions: fake.table)
        let transactionID = try MTPTransactionID(validating: 29)
        let header = MTPStreamingDataHeader(
            operationCode: .sendObject,
            transactionID: transactionID,
            payloadLength: 600
        )
        let response = try MTPContainer(
            type: .response,
            code: MTPResponseCode.ok.rawValue,
            transactionID: transactionID,
            payload: Data()
        ).encoded()
        fake.scriptedTransferBehaviors = [
            .immediate(status: LIBUSB_TRANSFER_COMPLETED, data: Data()),
            .immediate(status: LIBUSB_TRANSFER_COMPLETED, data: Data()),
            .immediate(status: LIBUSB_TRANSFER_COMPLETED, data: Data()),
            .immediate(status: LIBUSB_TRANSFER_COMPLETED, data: response),
        ]
        let transport = LibUSBTransport(handle: handle, functions: fake.table, readCapacity: 1_024)
        let payload = Data((0..<600).map { UInt8(truncatingIfNeeded: $0) })
        let source = BufferedMTPStreamSource(data: payload)

        _ = try transport.send(
            Data(repeating: 0xA5, count: 12),
            dataHeader: header,
            source: source,
            cancellation: MTPCancellationToken()
        )

        XCTAssertEqual(source.requestedMaximumLengths, [500, 100, 1])
        XCTAssertEqual(fake.submittedOutboundData.count, 3)
        if fake.submittedOutboundData.count == 3 {
            XCTAssertEqual(fake.submittedOutboundData[1], header.encoded() + payload.prefix(500))
            XCTAssertEqual(fake.submittedOutboundData[1].count, 512)
            XCTAssertEqual(fake.submittedOutboundData[2], Data(payload.suffix(100)))
            XCTAssertEqual(fake.submittedTransferFlags[1], 0)
            XCTAssertEqual(
                fake.submittedTransferFlags[2],
                UInt8(LIBUSB_TRANSFER_ADD_ZERO_PACKET.rawValue)
            )
        }
        handle.close()
        context.shutdown()
    }

    func testStreamingInboundRejectsResponseBeforeDataTerminal() throws {
        let fake = FakeLibUSBFunctions()
        let context = try LibUSBContext(functions: fake.table, startsEventLoop: false)
        let handle = try makeTestLibUSBDeviceHandle(context: context, functions: fake.table)
        let transactionID = try MTPTransactionID(validating: 23)
        let response = try MTPContainer(
            type: .response,
            code: MTPResponseCode.ok.rawValue,
            transactionID: transactionID,
            payload: Data()
        ).encoded()
        fake.scriptedTransferBehaviors = [
            .immediate(status: LIBUSB_TRANSFER_COMPLETED, data: Data()),
            .immediate(status: LIBUSB_TRANSFER_COMPLETED, data: response),
        ]
        let transport = LibUSBTransport(handle: handle, functions: fake.table, readCapacity: 64)

        XCTAssertThrowsError(
            try transport.receive(
                Data(repeating: 0xA5, count: 12),
                operationCode: .getObject,
                transactionID: transactionID,
                expectedPayloadLength: 1,
                sink: RecordingMTPStreamSink(),
                cancellation: MTPCancellationToken()
            )
        )
        handle.close()
        context.shutdown()
    }

    func testStreamingInboundRejectsResponseTransactionMismatch() throws {
        let fake = FakeLibUSBFunctions()
        let context = try LibUSBContext(functions: fake.table, startsEventLoop: false)
        let handle = try makeTestLibUSBDeviceHandle(context: context, functions: fake.table)
        let transactionID = try MTPTransactionID(validating: 24)
        let wrongTransactionID = try MTPTransactionID(validating: 25)
        let header = MTPStreamingDataHeader(
            operationCode: .getObject,
            transactionID: transactionID,
            payloadLength: 0
        )
        let response = try MTPContainer(
            type: .response,
            code: MTPResponseCode.ok.rawValue,
            transactionID: wrongTransactionID,
            payload: Data()
        ).encoded()
        fake.scriptedTransferBehaviors = [
            .immediate(status: LIBUSB_TRANSFER_COMPLETED, data: Data()),
            .immediate(status: LIBUSB_TRANSFER_COMPLETED, data: header.encoded()),
            .immediate(status: LIBUSB_TRANSFER_COMPLETED, data: response),
        ]
        let transport = LibUSBTransport(handle: handle, functions: fake.table, readCapacity: 64)

        XCTAssertThrowsError(
            try transport.receive(
                Data(repeating: 0xA5, count: 12),
                operationCode: .getObject,
                transactionID: transactionID,
                expectedPayloadLength: 0,
                sink: RecordingMTPStreamSink(),
                cancellation: MTPCancellationToken()
            )
        )
        handle.close()
        context.shutdown()
    }

    func testStreamingOutboundRejectsShortSourceBeforeReadingResponse() throws {
        let fake = FakeLibUSBFunctions()
        let context = try LibUSBContext(functions: fake.table, startsEventLoop: false)
        let handle = try makeTestLibUSBDeviceHandle(context: context, functions: fake.table)
        let transactionID = try MTPTransactionID(validating: 27)
        fake.scriptedTransferBehaviors = [
            .immediate(status: LIBUSB_TRANSFER_COMPLETED, data: Data()),
            .immediate(status: LIBUSB_TRANSFER_COMPLETED, data: Data()),
        ]
        let transport = LibUSBTransport(handle: handle, functions: fake.table, readCapacity: 64)

        XCTAssertThrowsError(
            try transport.send(
                Data(repeating: 0xA5, count: 12),
                dataHeader: MTPStreamingDataHeader(
                    operationCode: .sendObject,
                    transactionID: transactionID,
                    payloadLength: 4
                ),
                source: ArrayMTPStreamSource(chunks: [Data([1, 2])], length: 4),
                cancellation: MTPCancellationToken()
            )
        ) {
            guard case .protocolViolation = $0 as? MTPCoreError else {
                return XCTFail("expected protocol violation, got \($0)")
            }
        }
        XCTAssertEqual(fake.events.filter { $0 == "submitTransfer" }.count, 2)
        handle.close()
        context.shutdown()
    }

    func testStreamingOutboundRejectsSourceOverrunBeforeReadingResponse() throws {
        let fake = FakeLibUSBFunctions()
        let context = try LibUSBContext(functions: fake.table, startsEventLoop: false)
        let handle = try makeTestLibUSBDeviceHandle(context: context, functions: fake.table)
        let transactionID = try MTPTransactionID(validating: 28)
        fake.scriptedTransferBehaviors = [
            .immediate(status: LIBUSB_TRANSFER_COMPLETED, data: Data()),
            .immediate(status: LIBUSB_TRANSFER_COMPLETED, data: Data()),
        ]
        let transport = LibUSBTransport(handle: handle, functions: fake.table, readCapacity: 64)

        XCTAssertThrowsError(
            try transport.send(
                Data(repeating: 0xA5, count: 12),
                dataHeader: MTPStreamingDataHeader(
                    operationCode: .sendObject,
                    transactionID: transactionID,
                    payloadLength: 4
                ),
                source: ArrayMTPStreamSource(
                    chunks: [Data([1, 2, 3, 4]), Data([5])],
                    length: 4
                ),
                cancellation: MTPCancellationToken()
            )
        ) {
            guard case .protocolViolation = $0 as? MTPCoreError else {
                return XCTFail("expected protocol violation, got \($0)")
            }
        }
        XCTAssertEqual(fake.events.filter { $0 == "submitTransfer" }.count, 2)
        handle.close()
        context.shutdown()
    }

}

private final class RecordingMTPStreamSink: MTPStreamSink {
    private(set) var chunks: [Data] = []

    func write(_ data: Data) throws {
        chunks.append(data)
    }
}

private final class ArrayMTPStreamSource: MTPStreamSource, @unchecked Sendable {
    let length: UInt64?
    private let lock = NSLock()
    private var chunks: [Data]

    init(chunks: [Data], length: UInt64?) {
        self.chunks = chunks
        self.length = length
    }

    func read(maximumLength: Int) throws -> Data {
        try lock.withLock {
            guard !chunks.isEmpty else {
                return Data()
            }
            let chunk = chunks.removeFirst()
            guard chunk.count <= maximumLength else {
                throw MTPCoreError.protocolViolation("test source chunk exceeds requested length")
            }
            return chunk
        }
    }
}

private final class BufferedMTPStreamSource: MTPStreamSource, @unchecked Sendable {
    let length: UInt64?
    private let lock = NSLock()
    private let data: Data
    private var offset = 0
    private var requestedLengths: [Int] = []

    init(data: Data) {
        self.data = data
        self.length = UInt64(data.count)
    }

    var requestedMaximumLengths: [Int] {
        lock.withLock { requestedLengths }
    }

    func read(maximumLength: Int) throws -> Data {
        lock.withLock {
            requestedLengths.append(maximumLength)
            guard offset < data.count else {
                return Data()
            }
            let count = min(maximumLength, data.count - offset)
            defer { offset += count }
            return data.subdata(in: offset..<(offset + count))
        }
    }
}
