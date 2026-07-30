import Foundation
@testable import SwiftMTP

final class ScriptedUploadSource: MTPStreamSource {
    let length: UInt64?
    private var chunks: [Data]
    private let readError: MTPCoreError?

    init(
        length: UInt64?,
        chunks: [Data],
        readError: MTPCoreError? = nil
    ) {
        self.length = length
        self.chunks = chunks
        self.readError = readError
    }

    func read(maximumLength: Int) throws -> Data {
        if let readError {
            throw readError
        }
        guard !chunks.isEmpty else {
            return Data()
        }
        let chunk = chunks.removeFirst()
        guard chunk.count <= maximumLength else {
            throw MTPCoreError.protocolViolation(
                "test source chunk exceeds requested length"
            )
        }
        return chunk
    }
}

func makeUploadSession(
    transport: ScriptedMTPTransport,
    reporter: @escaping MTPUploadDiagnosticReporter = { _ in }
) -> MTPDeviceSession {
    MTPDeviceSession(
        transport: transport,
        sessionIDGenerator: { try MTPSessionID(validating: 7) },
        reportUploadDiagnostic: reporter
    )
}

func scriptedSendObjectInfoStep(
    storageID: MTPStorageID,
    name: String,
    size: UInt64,
    responseParameters: [UInt32]
) throws -> ScriptedMTPTransport.Step {
    scriptedMTPMetadataStep(
        operation: .sendObjectInfo,
        tid: 1,
        parameters: [storageID.rawValue, MTPObjectID.root.rawValue],
        outboundPayload: try MTPObjectInfoDataset.file(
            storageID: storageID,
            parentObject: .root,
            name: name,
            size: size
        ).encoded(),
        response: scriptedMTPResponse(
            .ok,
            tid: 1,
            parameters: responseParameters
        )
    )
}

func makeUploadFailureTransport(
    storageID: MTPStorageID,
    objectID: MTPObjectID,
    sendResult: Result<MTPStreamingTransactionResult, MTPCoreError>,
    cleanupResponse: MTPResponseCode?,
    includeClose: Bool,
    consumeSource: Bool = false,
    beforeRead: (() -> Void)? = nil
) throws -> ScriptedMTPTransport {
    var steps = [
        scriptedMTPMetadataStep(
            operation: .openSession,
            tid: 0,
            parameters: [7],
            response: scriptedMTPResponse(.ok, tid: 0)
        ),
        try scriptedSendObjectInfoStep(
            storageID: storageID,
            name: "failure.bin",
            size: 1,
            responseParameters: [
                storageID.rawValue,
                MTPObjectID.root.rawValue,
                objectID.rawValue,
            ]
        ),
    ]
    if let cleanupResponse {
        steps.append(
            scriptedMTPMetadataStep(
                operation: .deleteObject,
                tid: 3,
                parameters: [objectID.rawValue, 0],
                response: scriptedMTPResponse(cleanupResponse, tid: 3)
            )
        )
    }
    if includeClose {
        steps.append(
            scriptedMTPMetadataStep(
                operation: .closeSession,
                tid: 4,
                response: scriptedMTPResponse(.ok, tid: 4)
            )
        )
    }
    return ScriptedMTPTransport(
        steps: steps,
        sendSteps: [
            .init(
                expectedRequest: scriptedMTPCommand(
                    operation: .sendObject,
                    tid: 2
                ),
                expectedDataHeader: MTPStreamingDataHeader(
                    operationCode: .sendObject,
                    transactionID: try MTPTransactionID(validating: 2),
                    payloadLength: 1
                ),
                expectedSourceLength: 1,
                expectedChunks: consumeSource ? [Data([1])] : nil,
                beforeRead: beforeRead,
                result: sendResult
            ),
        ]
    )
}
