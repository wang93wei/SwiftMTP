import XCTest
@testable import SwiftMTP

final class MTPFilesystemSessionTests: XCTestCase {
    func testHandlesInfoCreateAndDeleteUseExactTransactionsAndResponseParameters() throws {
        let sessionID = try MTPSessionID(validating: 7)
        let storageID = try MTPStorageID(validating: 0x0001_0001)
        let objectID = try MTPObjectID(validating: 9)
        let info = try MTPObjectInfoDataset(
            storageID: storageID,
            objectFormat: 0x3000,
            objectSize: 42,
            parentObject: .root,
            filename: "a.txt"
        )
        let folder = try MTPObjectInfoDataset.folder(
            storageID: storageID,
            parentObject: .root,
            name: "相册😀"
        )
        let transport = ScriptedMTPTransport(steps: [
            step(.openSession, tid: 0, parameters: [7], response: scriptedMTPResponse(.ok, tid: 0)),
            step(
                .getObjectHandles,
                tid: 1,
                parameters: [storageID.rawValue, 0, MTPObjectID.root.rawValue],
                data: MTPUInt32Array(values: [objectID.rawValue]).encoded(),
                response: scriptedMTPResponse(.ok, tid: 1)
            ),
            step(
                .getObjectInfo,
                tid: 2,
                parameters: [objectID.rawValue],
                data: try info.encoded(),
                response: scriptedMTPResponse(.ok, tid: 2)
            ),
            step(
                .sendObjectInfo,
                tid: 3,
                parameters: [storageID.rawValue, MTPObjectID.root.rawValue],
                outbound: try folder.encoded(),
                response: scriptedMTPResponse(
                    .ok,
                    tid: 3,
                    parameters: [storageID.rawValue, MTPObjectID.root.rawValue, 10]
                )
            ),
            step(
                .deleteObject,
                tid: 4,
                parameters: [10, 0],
                response: scriptedMTPResponse(.ok, tid: 4)
            ),
            step(.closeSession, tid: 5, response: scriptedMTPResponse(.ok, tid: 5)),
        ])
        let session = MTPDeviceSession(transport: transport, sessionIDGenerator: { sessionID })

        try session.open()
        XCTAssertEqual(
            try session.getObjectHandles(storageID: storageID, parentID: .root),
            [objectID]
        )
        XCTAssertEqual(try session.getObjectInfo(objectID).filename, "a.txt")
        let folderID = try session.createFolder(
            storageID: storageID,
            parentID: .root,
            name: "相册😀"
        )
        XCTAssertEqual(folderID.rawValue, 10)
        try session.deleteObject(folderID)
        session.close()

        XCTAssertNoThrow(try transport.verifyConsumed())
    }

    func testRecoverableObjectResponseLeavesSessionUsable() throws {
        let sessionID = try MTPSessionID(validating: 9)
        let objectID = try MTPObjectID(validating: 3)
        let transport = ScriptedMTPTransport(steps: [
            step(.openSession, tid: 0, parameters: [9], response: scriptedMTPResponse(.ok, tid: 0)),
            step(
                .getObjectInfo,
                tid: 1,
                parameters: [3],
                response: scriptedMTPResponse(.invalidObjectHandle, tid: 1)
            ),
            step(
                .deleteObject,
                tid: 2,
                parameters: [3, 0],
                response: scriptedMTPResponse(.ok, tid: 2)
            ),
            step(.closeSession, tid: 3, response: scriptedMTPResponse(.ok, tid: 3)),
        ])
        let session = MTPDeviceSession(transport: transport, sessionIDGenerator: { sessionID })

        try session.open()
        XCTAssertThrowsError(try session.getObjectInfo(objectID)) {
            XCTAssertEqual($0 as? MTPCoreError, .response(code: .invalidObjectHandle))
        }
        XCTAssertNoThrow(try session.deleteObject(objectID))
        session.close()
        XCTAssertNoThrow(try transport.verifyConsumed())
    }

    func testCreateRejectsMissingMismatchedAndZeroResponseParameters() throws {
        let storageID = try MTPStorageID(validating: 1)
        let invalidParameters: [[UInt32]] = [
            [],
            [2, MTPObjectID.root.rawValue, 10],
            [storageID.rawValue, MTPObjectID.root.rawValue, 0],
        ]

        for parameters in invalidParameters {
            let sessionID = try MTPSessionID(validating: 11)
            let folder = try MTPObjectInfoDataset.folder(
                storageID: storageID,
                parentObject: .root,
                name: "new"
            )
            let transport = ScriptedMTPTransport(steps: [
                step(.openSession, tid: 0, parameters: [11], response: scriptedMTPResponse(.ok, tid: 0)),
                step(
                    .sendObjectInfo,
                    tid: 1,
                    parameters: [storageID.rawValue, MTPObjectID.root.rawValue],
                    outbound: try folder.encoded(),
                    response: scriptedMTPResponse(.ok, tid: 1, parameters: parameters)
                ),
            ])
            let session = MTPDeviceSession(
                transport: transport,
                sessionIDGenerator: { sessionID }
            )

            try session.open()
            XCTAssertThrowsError(
                try session.createFolder(
                    storageID: storageID,
                    parentID: .root,
                    name: "new"
                )
            ) {
                guard case .protocolViolation = $0 as? MTPCoreError else {
                    return XCTFail("expected protocol violation, got \($0)")
                }
            }
            XCTAssertThrowsError(try session.deleteObject(try MTPObjectID(validating: 1))) {
                XCTAssertEqual($0 as? MTPCoreError, .disconnected)
            }
            XCTAssertNoThrow(try transport.verifyConsumed())
        }
    }

    func testSessionNotOpenResponseInvalidatesSession() throws {
        let sessionID = try MTPSessionID(validating: 13)
        let objectID = try MTPObjectID(validating: 3)
        let transport = ScriptedMTPTransport(steps: [
            step(.openSession, tid: 0, parameters: [13], response: scriptedMTPResponse(.ok, tid: 0)),
            step(
                .getObjectInfo,
                tid: 1,
                parameters: [3],
                response: scriptedMTPResponse(.sessionNotOpen, tid: 1)
            ),
        ])
        let session = MTPDeviceSession(transport: transport, sessionIDGenerator: { sessionID })

        try session.open()
        XCTAssertThrowsError(try session.getObjectInfo(objectID)) {
            XCTAssertEqual($0 as? MTPCoreError, .response(code: .sessionNotOpen))
        }
        XCTAssertThrowsError(try session.deleteObject(objectID)) {
            XCTAssertEqual($0 as? MTPCoreError, .disconnected)
        }
        XCTAssertNoThrow(try transport.verifyConsumed())
    }

    func testEmptyHandlesSucceedAndInvalidWireHandleInvalidatesSession() throws {
        let storageID = try MTPStorageID(validating: 1)
        let emptyTransport = ScriptedMTPTransport(steps: [
            step(.openSession, tid: 0, parameters: [17], response: scriptedMTPResponse(.ok, tid: 0)),
            step(
                .getObjectHandles,
                tid: 1,
                parameters: [storageID.rawValue, 0, MTPObjectID.root.rawValue],
                data: MTPUInt32Array(values: []).encoded(),
                response: scriptedMTPResponse(.ok, tid: 1)
            ),
            step(.closeSession, tid: 2, response: scriptedMTPResponse(.ok, tid: 2)),
        ])
        let emptySession = MTPDeviceSession(
            transport: emptyTransport,
            sessionIDGenerator: { try! MTPSessionID(validating: 17) }
        )
        try emptySession.open()
        XCTAssertEqual(
            try emptySession.getObjectHandles(storageID: storageID, parentID: .root),
            []
        )
        emptySession.close()
        XCTAssertNoThrow(try emptyTransport.verifyConsumed())

        let invalidTransport = ScriptedMTPTransport(steps: [
            step(.openSession, tid: 0, parameters: [19], response: scriptedMTPResponse(.ok, tid: 0)),
            step(
                .getObjectHandles,
                tid: 1,
                parameters: [storageID.rawValue, 0, MTPObjectID.root.rawValue],
                data: MTPUInt32Array(values: [0]).encoded(),
                response: scriptedMTPResponse(.ok, tid: 1)
            ),
        ])
        let invalidSession = MTPDeviceSession(
            transport: invalidTransport,
            sessionIDGenerator: { try! MTPSessionID(validating: 19) }
        )
        try invalidSession.open()
        XCTAssertThrowsError(
            try invalidSession.getObjectHandles(storageID: storageID, parentID: .root)
        )
        XCTAssertThrowsError(
            try invalidSession.getObjectHandles(storageID: storageID, parentID: .root)
        ) {
            XCTAssertEqual($0 as? MTPCoreError, .disconnected)
        }
        XCTAssertNoThrow(try invalidTransport.verifyConsumed())
    }
}

private extension MTPFilesystemSessionTests {
    func step(
        _ operation: MTPOperationCode,
        tid: UInt32,
        parameters: [UInt32] = [],
        outbound: Data? = nil,
        data: Data? = nil,
        response: MTPContainer
    ) -> ScriptedMTPTransport.Step {
        var writer = MTPBinaryWriter()
        parameters.forEach { writer.write($0) }
        let transactionID = try! MTPTransactionID(validating: tid)
        let command = MTPContainer(
            type: .command,
            code: operation.rawValue,
            transactionID: transactionID,
            payload: writer.data
        )
        let outboundContainer = outbound.map {
            try! MTPContainer(
                type: .data,
                code: operation.rawValue,
                transactionID: transactionID,
                payload: $0
            ).encoded()
        }
        var incoming = Data()
        if let data {
            incoming.append(
                try! MTPContainer(
                    type: .data,
                    code: operation.rawValue,
                    transactionID: transactionID,
                    payload: data
                ).encoded()
            )
        }
        incoming.append(try! response.encoded())
        return ScriptedMTPTransport.Step(
            expectedRequest: try! command.encoded(),
            expectedOutboundData: outboundContainer,
            result: .success([incoming])
        )
    }

}
