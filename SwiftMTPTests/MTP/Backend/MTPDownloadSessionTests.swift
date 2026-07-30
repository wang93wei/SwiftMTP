import XCTest
@testable import SwiftMTP

final class MTPDownloadSessionTests: XCTestCase {
    func testDownloadStreamsFragmentedObjectAndReportsMeasuredProgress() throws {
        let objectID = try MTPObjectID(validating: 42)
        let payload = Data("hello".utf8)
        let transport = ScriptedMTPTransport(
            steps: [
                scriptedMTPMetadataStep(
                    operation: .openSession,
                    tid: 0,
                    parameters: [7],
                    response: scriptedMTPResponse(.ok, tid: 0)
                ),
                scriptedMTPMetadataStep(
                    operation: .getObjectInfo,
                    tid: 1,
                    parameters: [objectID.rawValue],
                    inboundPayload: try objectInfo(size: UInt64(payload.count)).encoded(),
                    response: scriptedMTPResponse(.ok, tid: 1)
                ),
                scriptedMTPMetadataStep(
                    operation: .closeSession,
                    tid: 3,
                    response: scriptedMTPResponse(.ok, tid: 3)
                ),
            ],
            receiveSteps: [
                ScriptedMTPTransport.ReceiveStep(
                    expectedRequest: scriptedMTPCommand(
                        operation: .getObject,
                        tid: 2,
                        parameters: [objectID.rawValue]
                    ),
                    expectedOperationCode: .getObject,
                    expectedTransactionID: try MTPTransactionID(validating: 2),
                    expectedPayloadLength: UInt64(payload.count),
                    chunks: [payload.prefix(2), payload.dropFirst(2)],
                    result: .success(
                        MTPStreamingTransactionResult(
                            responseCode: .ok,
                            responseParameters: [],
                            transferredByteCount: UInt64(payload.count)
                        )
                    )
                ),
            ]
        )
        let session = MTPDeviceSession(
            transport: transport,
            sessionIDGenerator: { try MTPSessionID(validating: 7) }
        )
        let sink = RecordingDownloadSink()
        var progress: [UInt64] = []

        try session.open()
        let result = try session.download(
            objectID: objectID,
            sink: sink,
            progress: { progress.append($0) },
            cancellation: MTPCancellationToken()
        )
        session.close()

        XCTAssertEqual(sink.data, payload)
        XCTAssertEqual(progress, [2, 5])
        XCTAssertEqual(result.expectedByteCount, 5)
        XCTAssertEqual(result.transferredByteCount, 5)
        try transport.verifyConsumed()
    }

    func testSentinelObjectSizeUsesUInt64ObjectSizeProperty() throws {
        let objectID = try MTPObjectID(validating: 44)
        let resolvedSize: UInt64 = UInt64(UInt32.max) + 17
        var sizeWriter = MTPBinaryWriter()
        sizeWriter.write(resolvedSize)
        let transport = ScriptedMTPTransport(
            steps: [
                scriptedMTPMetadataStep(
                    operation: .openSession,
                    tid: 0,
                    parameters: [7],
                    response: scriptedMTPResponse(.ok, tid: 0)
                ),
                scriptedMTPMetadataStep(
                    operation: .getObjectInfo,
                    tid: 1,
                    parameters: [objectID.rawValue],
                    inboundPayload: try objectInfo(size: UInt64(UInt32.max)).encoded(),
                    response: scriptedMTPResponse(.ok, tid: 1)
                ),
                scriptedMTPMetadataStep(
                    operation: .getObjectPropValue,
                    tid: 2,
                    parameters: [
                        objectID.rawValue,
                        UInt32(MTPObjectPropertyCode.objectSize.rawValue),
                    ],
                    inboundPayload: sizeWriter.data,
                    response: scriptedMTPResponse(.ok, tid: 2)
                ),
                scriptedMTPMetadataStep(
                    operation: .closeSession,
                    tid: 4,
                    response: scriptedMTPResponse(.ok, tid: 4)
                ),
            ],
            receiveSteps: [
                ScriptedMTPTransport.ReceiveStep(
                    expectedRequest: scriptedMTPCommand(
                        operation: .getObject,
                        tid: 3,
                        parameters: [objectID.rawValue]
                    ),
                    expectedOperationCode: .getObject,
                    expectedTransactionID: try MTPTransactionID(validating: 3),
                    expectedPayloadLength: resolvedSize,
                    chunks: [],
                    result: .success(
                        MTPStreamingTransactionResult(
                            responseCode: .generalError,
                            responseParameters: [],
                            transferredByteCount: 0
                        )
                    )
                ),
            ]
        )
        let session = MTPDeviceSession(
            transport: transport,
            sessionIDGenerator: { try MTPSessionID(validating: 7) }
        )

        try session.open()
        XCTAssertThrowsError(
            try session.download(
                objectID: objectID,
                sink: RecordingDownloadSink(),
                progress: { _ in },
                cancellation: MTPCancellationToken()
            )
        ) {
            XCTAssertEqual($0 as? MTPCoreError, .response(code: .generalError))
        }
        session.close()
        try transport.verifyConsumed()
    }

    func testUnsupportedObjectSizePropertyLeavesExpectedSizeIndeterminate() throws {
        let objectID = try MTPObjectID(validating: 45)
        let payload = Data([1, 2, 3])
        let transport = ScriptedMTPTransport(
            steps: [
                scriptedMTPMetadataStep(
                    operation: .openSession,
                    tid: 0,
                    parameters: [7],
                    response: scriptedMTPResponse(.ok, tid: 0)
                ),
                scriptedMTPMetadataStep(
                    operation: .getObjectInfo,
                    tid: 1,
                    parameters: [objectID.rawValue],
                    inboundPayload: try objectInfo(size: UInt64(UInt32.max)).encoded(),
                    response: scriptedMTPResponse(.ok, tid: 1)
                ),
                scriptedMTPMetadataStep(
                    operation: .getObjectPropValue,
                    tid: 2,
                    parameters: [
                        objectID.rawValue,
                        UInt32(MTPObjectPropertyCode.objectSize.rawValue),
                    ],
                    response: scriptedMTPResponse(.operationNotSupported, tid: 2)
                ),
                scriptedMTPMetadataStep(
                    operation: .closeSession,
                    tid: 4,
                    response: scriptedMTPResponse(.ok, tid: 4)
                ),
            ],
            receiveSteps: [
                ScriptedMTPTransport.ReceiveStep(
                    expectedRequest: scriptedMTPCommand(
                        operation: .getObject,
                        tid: 3,
                        parameters: [objectID.rawValue]
                    ),
                    expectedOperationCode: .getObject,
                    expectedTransactionID: try MTPTransactionID(validating: 3),
                    expectedPayloadLength: nil,
                    chunks: [payload],
                    result: .success(
                        MTPStreamingTransactionResult(
                            responseCode: .ok,
                            responseParameters: [],
                            transferredByteCount: 3
                        )
                    )
                ),
            ]
        )
        let session = MTPDeviceSession(
            transport: transport,
            sessionIDGenerator: { try MTPSessionID(validating: 7) }
        )

        try session.open()
        let result = try session.download(
            objectID: objectID,
            sink: RecordingDownloadSink(),
            progress: { _ in },
            cancellation: MTPCancellationToken()
        )
        session.close()

        XCTAssertNil(result.expectedByteCount)
        XCTAssertEqual(result.transferredByteCount, 3)
        try transport.verifyConsumed()
    }

    func testKnownObjectSizeRejectsShortStreamAndInvalidatesSession() throws {
        try assertSizeMismatch(expected: 5, payload: Data([1, 2, 3]))
    }

    func testKnownObjectSizeRejectsOverrunAndInvalidatesSession() throws {
        try assertSizeMismatch(expected: 2, payload: Data([1, 2, 3]))
    }

    func testTimeoutCancellationAndDisconnectInvalidateWithoutReplay() throws {
        for error in [
            MTPCoreError.timeout,
            .cancelled,
            .disconnected,
        ] {
            try assertTerminalTransportErrorInvalidates(error)
        }
    }

    func testMalformedObjectSizePropertyInvalidatesSession() throws {
        let objectID = try MTPObjectID(validating: 47)
        var truncatedSize = MTPBinaryWriter()
        truncatedSize.write(UInt32(8))
        let transport = ScriptedMTPTransport(
            steps: [
                scriptedMTPMetadataStep(
                    operation: .openSession,
                    tid: 0,
                    parameters: [7],
                    response: scriptedMTPResponse(.ok, tid: 0)
                ),
                scriptedMTPMetadataStep(
                    operation: .getObjectInfo,
                    tid: 1,
                    parameters: [objectID.rawValue],
                    inboundPayload: try objectInfo(size: UInt64(UInt32.max)).encoded(),
                    response: scriptedMTPResponse(.ok, tid: 1)
                ),
                scriptedMTPMetadataStep(
                    operation: .getObjectPropValue,
                    tid: 2,
                    parameters: [
                        objectID.rawValue,
                        UInt32(MTPObjectPropertyCode.objectSize.rawValue),
                    ],
                    inboundPayload: truncatedSize.data,
                    response: scriptedMTPResponse(.ok, tid: 2)
                ),
            ]
        )
        let session = MTPDeviceSession(
            transport: transport,
            sessionIDGenerator: { try MTPSessionID(validating: 7) }
        )

        try session.open()
        XCTAssertThrowsError(
            try session.download(
                objectID: objectID,
                sink: RecordingDownloadSink(),
                progress: { _ in },
                cancellation: MTPCancellationToken()
            )
        ) {
            guard case .protocolViolation = $0 as? MTPCoreError else {
                return XCTFail("expected malformed UInt64 property failure, got \($0)")
            }
        }
        XCTAssertThrowsError(try session.getStorageIDs()) {
            XCTAssertEqual($0 as? MTPCoreError, .disconnected)
        }
        try transport.verifyConsumed()
    }

    private func assertSizeMismatch(expected: UInt64, payload: Data) throws {
        let objectID = try MTPObjectID(validating: 46)
        let transport = ScriptedMTPTransport(
            steps: [
                scriptedMTPMetadataStep(
                    operation: .openSession,
                    tid: 0,
                    parameters: [7],
                    response: scriptedMTPResponse(.ok, tid: 0)
                ),
                scriptedMTPMetadataStep(
                    operation: .getObjectInfo,
                    tid: 1,
                    parameters: [objectID.rawValue],
                    inboundPayload: try objectInfo(size: expected).encoded(),
                    response: scriptedMTPResponse(.ok, tid: 1)
                ),
            ],
            receiveSteps: [
                ScriptedMTPTransport.ReceiveStep(
                    expectedRequest: scriptedMTPCommand(
                        operation: .getObject,
                        tid: 2,
                        parameters: [objectID.rawValue]
                    ),
                    expectedOperationCode: .getObject,
                    expectedTransactionID: try MTPTransactionID(validating: 2),
                    expectedPayloadLength: expected,
                    chunks: [payload],
                    result: .success(
                        MTPStreamingTransactionResult(
                            responseCode: .ok,
                            responseParameters: [],
                            transferredByteCount: UInt64(payload.count)
                        )
                    )
                ),
            ]
        )
        let session = MTPDeviceSession(
            transport: transport,
            sessionIDGenerator: { try MTPSessionID(validating: 7) }
        )

        try session.open()
        XCTAssertThrowsError(
            try session.download(
                objectID: objectID,
                sink: RecordingDownloadSink(),
                progress: { _ in },
                cancellation: MTPCancellationToken()
            )
        ) {
            guard case .protocolViolation = $0 as? MTPCoreError else {
                return XCTFail("expected byte-count violation, got \($0)")
            }
        }
        XCTAssertThrowsError(try session.getStorageIDs()) {
            XCTAssertEqual($0 as? MTPCoreError, .disconnected)
        }
        try transport.verifyConsumed()
    }

    private func assertTerminalTransportErrorInvalidates(
        _ error: MTPCoreError
    ) throws {
        let objectID = try MTPObjectID(validating: 48)
        let transport = ScriptedMTPTransport(
            steps: [
                scriptedMTPMetadataStep(
                    operation: .openSession,
                    tid: 0,
                    parameters: [7],
                    response: scriptedMTPResponse(.ok, tid: 0)
                ),
                scriptedMTPMetadataStep(
                    operation: .getObjectInfo,
                    tid: 1,
                    parameters: [objectID.rawValue],
                    inboundPayload: try objectInfo(size: 1).encoded(),
                    response: scriptedMTPResponse(.ok, tid: 1)
                ),
            ],
            receiveSteps: [
                ScriptedMTPTransport.ReceiveStep(
                    expectedRequest: scriptedMTPCommand(
                        operation: .getObject,
                        tid: 2,
                        parameters: [objectID.rawValue]
                    ),
                    expectedOperationCode: .getObject,
                    expectedTransactionID: try MTPTransactionID(validating: 2),
                    expectedPayloadLength: 1,
                    chunks: [],
                    result: .failure(error)
                ),
            ]
        )
        let session = MTPDeviceSession(
            transport: transport,
            sessionIDGenerator: { try MTPSessionID(validating: 7) }
        )

        try session.open()
        XCTAssertThrowsError(
            try session.download(
                objectID: objectID,
                sink: RecordingDownloadSink(),
                progress: { _ in },
                cancellation: MTPCancellationToken()
            )
        ) {
            XCTAssertEqual($0 as? MTPCoreError, error)
        }
        XCTAssertThrowsError(try session.getStorageIDs()) {
            XCTAssertEqual($0 as? MTPCoreError, .disconnected)
        }
        try transport.verifyConsumed()
    }
}

private final class RecordingDownloadSink: MTPStreamSink {
    private(set) var data = Data()

    func write(_ data: Data) throws {
        self.data.append(data)
    }
}

private func objectInfo(size: UInt64) throws -> MTPObjectInfoDataset {
    try MTPObjectInfoDataset(
        storageID: MTPStorageID(validating: 1),
        objectFormat: 0x3000,
        objectSize: size,
        parentObject: .root,
        filename: "fixture.bin"
    )
}
