import XCTest
@testable import SwiftMTP

final class MTPUploadCompensationSessionTests: XCTestCase {
    func testOrdinarySendFailureDeletesOrphanAndPreservesPrimaryError() throws {
        let storageID = try MTPStorageID(validating: 1)
        let objectID = try MTPObjectID(validating: 9)
        var diagnostics: [MTPUploadCompensationDiagnostic] = []
        let transport = try makeUploadFailureTransport(
            storageID: storageID,
            objectID: objectID,
            sendResult: .success(
                MTPStreamingTransactionResult(
                    responseCode: .generalError,
                    responseParameters: [],
                    transferredByteCount: 1
                )
            ),
            cleanupResponse: .ok,
            includeClose: true
        )
        let session = makeUploadSession(transport: transport) {
            diagnostics.append($0)
        }

        try session.open()
        XCTAssertThrowsError(
            try session.upload(
                storageID: storageID,
                parentID: .root,
                name: "failure.bin",
                size: 1,
                modificationDateString: "",
                source: ScriptedUploadSource(length: 1, chunks: [Data([1])]),
                progress: { _ in },
                cancellation: MTPCancellationToken()
            )
        ) {
            XCTAssertEqual($0 as? MTPCoreError, .response(code: .generalError))
        }
        session.close()

        XCTAssertEqual(
            diagnostics,
            [
                MTPUploadCompensationDiagnostic(
                    objectID: objectID,
                    primaryError: .response(code: .generalError),
                    outcome: .removed
                ),
            ]
        )
        try transport.verifyConsumed()
    }

    func testCleanupFailureIsTypedWithoutReplacingPrimaryError() throws {
        let storageID = try MTPStorageID(validating: 1)
        let objectID = try MTPObjectID(validating: 9)
        var diagnostics: [MTPUploadCompensationDiagnostic] = []
        let transport = try makeUploadFailureTransport(
            storageID: storageID,
            objectID: objectID,
            sendResult: .success(
                MTPStreamingTransactionResult(
                    responseCode: .generalError,
                    responseParameters: [],
                    transferredByteCount: 1
                )
            ),
            cleanupResponse: .generalError,
            includeClose: true
        )
        let session = makeUploadSession(transport: transport) {
            diagnostics.append($0)
        }

        try session.open()
        XCTAssertThrowsError(
            try session.upload(
                storageID: storageID,
                parentID: .root,
                name: "failure.bin",
                size: 1,
                modificationDateString: "",
                source: ScriptedUploadSource(length: 1, chunks: [Data([1])]),
                progress: { _ in },
                cancellation: MTPCancellationToken()
            )
        ) {
            XCTAssertEqual($0 as? MTPCoreError, .response(code: .generalError))
        }
        session.close()

        XCTAssertEqual(
            diagnostics.first?.outcome,
            .failed(.response(code: .generalError))
        )
        XCTAssertEqual(
            diagnostics.first?.primaryError,
            .response(code: .generalError)
        )
        try transport.verifyConsumed()
    }

    func testTerminalFailureSkipsUnsafeCleanupAndDoesNotReplayMutation() throws {
        for terminalError in [
            MTPCoreError.timeout,
            .disconnected,
            .cancelled,
        ] {
            let storageID = try MTPStorageID(validating: 1)
            let objectID = try MTPObjectID(validating: 9)
            var diagnostics: [MTPUploadCompensationDiagnostic] = []
            let transport = try makeUploadFailureTransport(
                storageID: storageID,
                objectID: objectID,
                sendResult: .failure(terminalError),
                cleanupResponse: nil,
                includeClose: false
            )
            let session = makeUploadSession(transport: transport) {
                diagnostics.append($0)
            }

            try session.open()
            XCTAssertThrowsError(
                try session.upload(
                    storageID: storageID,
                    parentID: .root,
                    name: "failure.bin",
                    size: 1,
                    modificationDateString: "",
                    source: ScriptedUploadSource(
                        length: 1,
                        chunks: [Data([1])]
                    ),
                    progress: { _ in },
                    cancellation: MTPCancellationToken()
                )
            ) {
                XCTAssertEqual($0 as? MTPCoreError, terminalError)
            }
            XCTAssertEqual(diagnostics.first?.outcome, .skippedOrphanRisk)
            XCTAssertThrowsError(try session.getStorageIDs()) {
                XCTAssertEqual($0 as? MTPCoreError, .disconnected)
            }
            session.close()
            try transport.verifyConsumed()
        }
    }

    func testLocalReadFailureCompensatesAndKeepsSessionUsable() throws {
        let storageID = try MTPStorageID(validating: 1)
        let objectID = try MTPObjectID(validating: 9)
        var diagnostics: [MTPUploadCompensationDiagnostic] = []
        let transport = try makeUploadFailureTransport(
            storageID: storageID,
            objectID: objectID,
            sendResult: .success(
                MTPStreamingTransactionResult(
                    responseCode: .ok,
                    responseParameters: [],
                    transferredByteCount: 1
                )
            ),
            cleanupResponse: .ok,
            includeClose: true,
            consumeSource: true
        )
        let session = makeUploadSession(transport: transport) {
            diagnostics.append($0)
        }

        try session.open()
        XCTAssertThrowsError(
            try session.upload(
                storageID: storageID,
                parentID: .root,
                name: "failure.bin",
                size: 1,
                modificationDateString: "",
                source: ScriptedUploadSource(
                    length: 1,
                    chunks: [],
                    readError: .localFileIO("fixture read failed")
                ),
                progress: { _ in },
                cancellation: MTPCancellationToken()
            )
        ) {
            XCTAssertEqual(
                $0 as? MTPCoreError,
                .localFileIO("fixture read failed")
            )
        }
        session.close()

        XCTAssertEqual(diagnostics.first?.outcome, .removed)
        try transport.verifyConsumed()
    }

    func testMidStreamCancellationSkipsUnsafeCleanup() throws {
        let storageID = try MTPStorageID(validating: 1)
        let objectID = try MTPObjectID(validating: 9)
        let cancellation = MTPCancellationToken()
        var diagnostics: [MTPUploadCompensationDiagnostic] = []
        let transport = try makeUploadFailureTransport(
            storageID: storageID,
            objectID: objectID,
            sendResult: .success(
                MTPStreamingTransactionResult(
                    responseCode: .ok,
                    responseParameters: [],
                    transferredByteCount: 1
                )
            ),
            cleanupResponse: nil,
            includeClose: false,
            consumeSource: true,
            beforeRead: { cancellation.cancel() }
        )
        let session = makeUploadSession(transport: transport) {
            diagnostics.append($0)
        }

        try session.open()
        XCTAssertThrowsError(
            try session.upload(
                storageID: storageID,
                parentID: .root,
                name: "failure.bin",
                size: 1,
                modificationDateString: "",
                source: ScriptedUploadSource(length: 1, chunks: [Data([1])]),
                progress: { _ in },
                cancellation: cancellation
            )
        ) {
            XCTAssertEqual($0 as? MTPCoreError, .cancelled)
        }

        XCTAssertEqual(diagnostics.first?.outcome, .skippedOrphanRisk)
        session.close()
        try transport.verifyConsumed()
    }
}
