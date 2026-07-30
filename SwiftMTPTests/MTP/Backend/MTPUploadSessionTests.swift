import XCTest
@testable import SwiftMTP

final class MTPUploadSessionTests: XCTestCase {
    func testUploadSendsExactObjectInfoAndPayloadAndReportsMeasuredProgress() throws {
        let storageID = try MTPStorageID(validating: 1)
        let objectID = try MTPObjectID(validating: 9)
        let payloadChunks = [Data([1, 2]), Data([3, 4, 5])]
        let source = ScriptedUploadSource(length: 5, chunks: payloadChunks)
        let transport = try uploadTransport(
            storageID: storageID,
            objectID: objectID,
            name: "文档😀.bin",
            size: 5,
            sendStep: .init(
                expectedRequest: scriptedMTPCommand(operation: .sendObject, tid: 2),
                expectedDataHeader: MTPStreamingDataHeader(
                    operationCode: .sendObject,
                    transactionID: MTPTransactionID(validating: 2),
                    payloadLength: 5
                ),
                expectedSourceLength: 5,
                expectedChunks: payloadChunks,
                maximumReadLength: 3,
                result: .success(
                    MTPStreamingTransactionResult(
                        responseCode: .ok,
                        responseParameters: [],
                        transferredByteCount: 5
                    )
                )
            ),
            closingTransactionID: 3
        )
        let session = makeUploadSession(transport: transport)
        var progress: [UInt64] = []

        try session.open()
        let result = try session.upload(
            storageID: storageID,
            parentID: .root,
            name: "文档😀.bin",
            size: 5,
            modificationDateString: "",
            source: source,
            progress: { progress.append($0) },
            cancellation: MTPCancellationToken()
        )
        session.close()

        XCTAssertEqual(result, MTPUploadResult(objectID: objectID, transferredByteCount: 5))
        XCTAssertEqual(progress, [2, 5])
        try transport.verifyConsumed()
    }

    func testEmptyUploadAndPayloadLengthSentinelBoundaries() throws {
        let maximumExactPayload = UInt64(UInt32.max) - MTPContainer.headerLength
        for (size, headerLength) in [
            (UInt64(0), Optional(UInt64(0))),
            (maximumExactPayload, Optional(maximumExactPayload)),
            (maximumExactPayload + 1, nil),
        ] {
            let storageID = try MTPStorageID(validating: 1)
            let objectID = try MTPObjectID(validating: 9)
            let transport = try uploadTransport(
                storageID: storageID,
                objectID: objectID,
                name: "boundary.bin",
                size: size,
                sendStep: .init(
                    expectedRequest: scriptedMTPCommand(operation: .sendObject, tid: 2),
                    expectedDataHeader: MTPStreamingDataHeader(
                        operationCode: .sendObject,
                        transactionID: MTPTransactionID(validating: 2),
                        payloadLength: headerLength
                    ),
                    expectedSourceLength: size,
                    result: .success(
                        MTPStreamingTransactionResult(
                            responseCode: .ok,
                            responseParameters: [],
                            transferredByteCount: size
                        )
                    )
                ),
                closingTransactionID: 3
            )
            let session = makeUploadSession(transport: transport)
            var progress: [UInt64] = []

            try session.open()
            let result = try session.upload(
                storageID: storageID,
                parentID: .root,
                name: "boundary.bin",
                size: size,
                modificationDateString: "",
                source: ScriptedUploadSource(length: size, chunks: []),
                progress: { progress.append($0) },
                cancellation: MTPCancellationToken()
            )
            session.close()

            XCTAssertEqual(result.transferredByteCount, size)
            XCTAssertEqual(progress, size == 0 ? [] : [size])
            try transport.verifyConsumed()
        }
    }

    func testSendObjectInfoRequiresExactlyThreeMatchingResponseParameters() throws {
        let storageID = try MTPStorageID(validating: 1)
        let transport = ScriptedMTPTransport(
            steps: [
                scriptedMTPMetadataStep(
                    operation: .openSession,
                    tid: 0,
                    parameters: [7],
                    response: scriptedMTPResponse(.ok, tid: 0)
                ),
                try scriptedSendObjectInfoStep(
                    storageID: storageID,
                    name: "mismatch.bin",
                    size: 0,
                    responseParameters: [
                        storageID.rawValue,
                        MTPObjectID.root.rawValue,
                    ]
                ),
            ]
        )
        let session = makeUploadSession(transport: transport)

        try session.open()
        XCTAssertThrowsError(
            try session.upload(
                storageID: storageID,
                parentID: .root,
                name: "mismatch.bin",
                size: 0,
                modificationDateString: "",
                source: ScriptedUploadSource(length: 0, chunks: []),
                progress: { _ in },
                cancellation: MTPCancellationToken()
            )
        ) {
            guard case .protocolViolation = $0 as? MTPCoreError else {
                return XCTFail("expected protocol violation, got \($0)")
            }
        }
        XCTAssertThrowsError(try session.getStorageIDs()) {
            XCTAssertEqual($0 as? MTPCoreError, .disconnected)
        }
        try transport.verifyConsumed()
    }

    private func uploadTransport(
        storageID: MTPStorageID,
        objectID: MTPObjectID,
        name: String,
        size: UInt64,
        sendStep: ScriptedMTPTransport.SendStep,
        closingTransactionID: UInt32
    ) throws -> ScriptedMTPTransport {
        ScriptedMTPTransport(
            steps: [
                scriptedMTPMetadataStep(
                    operation: .openSession,
                    tid: 0,
                    parameters: [7],
                    response: scriptedMTPResponse(.ok, tid: 0)
                ),
                try scriptedSendObjectInfoStep(
                    storageID: storageID,
                    name: name,
                    size: size,
                    responseParameters: [
                        storageID.rawValue,
                        MTPObjectID.root.rawValue,
                        objectID.rawValue,
                    ]
                ),
                scriptedMTPMetadataStep(
                    operation: .closeSession,
                    tid: closingTransactionID,
                    response: scriptedMTPResponse(.ok, tid: closingTransactionID)
                ),
            ],
            sendSteps: [sendStep]
        )
    }

}
