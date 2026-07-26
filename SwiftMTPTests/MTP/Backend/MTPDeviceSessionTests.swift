import XCTest
@testable import SwiftMTP

final class MTPDeviceSessionTests: XCTestCase {
    func testOpenDiscoveryAndCloseUseExactTransactionIDs() throws {
        let sessionID = try MTPSessionID(validating: 7)
        let storageID = try MTPStorageID(validating: 0x0001_0001)
        let deviceInfo = makeDeviceInfoPayload()
        let storageInfo = makeStorageInfoPayload()

        let transport = ScriptedMTPTransport(steps: [
            step(
                operation: .openSession,
                transactionID: 0,
                parameters: [sessionID.rawValue],
                containers: [response(.ok, transactionID: 0)]
            ),
            step(
                operation: .getDeviceInfo,
                transactionID: 1,
                containers: [
                    data(.getDeviceInfo, transactionID: 1, payload: deviceInfo),
                    response(.ok, transactionID: 1),
                ]
            ),
            step(
                operation: .getStorageIDs,
                transactionID: 2,
                containers: [
                    data(
                        .getStorageIDs,
                        transactionID: 2,
                        payload: MTPUInt32Array(values: [storageID.rawValue]).encoded()
                    ),
                    response(.ok, transactionID: 2),
                ]
            ),
            step(
                operation: .getStorageInfo,
                transactionID: 3,
                parameters: [storageID.rawValue],
                containers: [
                    data(.getStorageInfo, transactionID: 3, payload: storageInfo),
                    response(.ok, transactionID: 3),
                ]
            ),
            step(
                operation: .closeSession,
                transactionID: 4,
                containers: [response(.ok, transactionID: 4)]
            ),
        ])
        let session = MTPDeviceSession(
            transport: transport,
            sessionIDGenerator: { sessionID }
        )

        try session.open()
        XCTAssertEqual(try session.getDeviceInfo().model, "Phone X")
        XCTAssertEqual(try session.getStorageIDs(), [storageID])
        XCTAssertEqual(
            try session.getStorageInfo(storageID).description,
            "Internal shared storage"
        )
        session.close()

        XCTAssertNoThrow(try transport.verifyConsumed())
        XCTAssertThrowsError(try session.getDeviceInfo()) {
            XCTAssertEqual($0 as? MTPCoreError, .disconnected)
        }
    }

    func testSessionAlreadyOpenClosesStaleSessionAndRetriesWithTransactionZero() throws {
        let sessionID = try MTPSessionID(validating: 9)
        let transport = ScriptedMTPTransport(steps: [
            step(
                operation: .openSession,
                transactionID: 0,
                parameters: [sessionID.rawValue],
                containers: [response(.sessionAlreadyOpen, transactionID: 0)]
            ),
            step(
                operation: .closeSession,
                transactionID: 0,
                containers: [response(.ok, transactionID: 0)]
            ),
            step(
                operation: .openSession,
                transactionID: 0,
                parameters: [sessionID.rawValue],
                containers: [response(.ok, transactionID: 0)]
            ),
            step(
                operation: .closeSession,
                transactionID: 1,
                containers: [response(.ok, transactionID: 1)]
            ),
        ])
        let session = MTPDeviceSession(
            transport: transport,
            sessionIDGenerator: { sessionID }
        )

        try session.open()
        session.close()

        XCTAssertNoThrow(try transport.verifyConsumed())
    }

    func testResponseTransactionMismatchInvalidatesSession() throws {
        let sessionID = try MTPSessionID(validating: 11)
        let transport = ScriptedMTPTransport(steps: [
            step(
                operation: .openSession,
                transactionID: 0,
                parameters: [sessionID.rawValue],
                containers: [response(.ok, transactionID: 0)]
            ),
            step(
                operation: .getDeviceInfo,
                transactionID: 1,
                containers: [response(.ok, transactionID: 99)]
            ),
        ])
        let session = MTPDeviceSession(
            transport: transport,
            sessionIDGenerator: { sessionID }
        )

        try session.open()
        XCTAssertThrowsError(try session.getDeviceInfo()) {
            guard case .protocolViolation = $0 as? MTPCoreError else {
                return XCTFail("expected protocolViolation, got \($0)")
            }
        }
        XCTAssertThrowsError(try session.getStorageIDs()) {
            XCTAssertEqual($0 as? MTPCoreError, .disconnected)
        }
    }

    func testFailedOpenInvalidatesInstanceAndCannotBeRetried() throws {
        let sessionID = try MTPSessionID(validating: 13)
        var payload = MTPBinaryWriter()
        payload.write(sessionID.rawValue)
        let request = MTPContainer(
            type: .command,
            code: MTPOperationCode.openSession.rawValue,
            transactionID: try MTPTransactionID(validating: 0),
            payload: payload.data
        )
        let transport = ScriptedMTPTransport(steps: [
            .init(
                expectedRequest: try request.encoded(),
                result: .failure(.timeout)
            ),
        ])
        let session = MTPDeviceSession(
            transport: transport,
            sessionIDGenerator: { sessionID }
        )

        XCTAssertThrowsError(try session.open()) {
            XCTAssertEqual($0 as? MTPCoreError, .timeout)
        }
        XCTAssertThrowsError(try session.open()) {
            XCTAssertEqual($0 as? MTPCoreError, .disconnected)
        }
        XCTAssertNoThrow(try transport.verifyConsumed())
    }

    func testResponseBeforeDataIsRejectedAndInvalidatesSession() throws {
        let sessionID = try MTPSessionID(validating: 17)
        let transactionID = try MTPTransactionID(validating: 1)
        let transport = ScriptedMTPTransport(steps: [
            step(
                operation: .openSession,
                transactionID: 0,
                parameters: [sessionID.rawValue],
                containers: [response(.ok, transactionID: 0)]
            ),
            step(
                operation: .getDeviceInfo,
                transactionID: 1,
                containers: [
                    response(.ok, transactionID: 1),
                    MTPContainer(
                        type: .data,
                        code: MTPOperationCode.getDeviceInfo.rawValue,
                        transactionID: transactionID,
                        payload: makeDeviceInfoPayload()
                    ),
                ]
            ),
        ])
        let session = MTPDeviceSession(
            transport: transport,
            sessionIDGenerator: { sessionID }
        )

        try session.open()
        XCTAssertThrowsError(try session.getDeviceInfo()) {
            guard case .protocolViolation = $0 as? MTPCoreError else {
                return XCTFail("expected protocol violation, got \($0)")
            }
        }
        XCTAssertThrowsError(try session.getStorageIDs()) {
            XCTAssertEqual($0 as? MTPCoreError, .disconnected)
        }
    }

    func testNonAlignedResponseParametersAreRejected() throws {
        let sessionID = try MTPSessionID(validating: 19)
        let malformedResponse = MTPContainer(
            type: .response,
            code: MTPResponseCode.ok.rawValue,
            transactionID: try MTPTransactionID(validating: 0),
            payload: Data([0x01])
        )
        let transport = ScriptedMTPTransport(steps: [
            step(
                operation: .openSession,
                transactionID: 0,
                parameters: [sessionID.rawValue],
                containers: [malformedResponse]
            ),
        ])
        let session = MTPDeviceSession(
            transport: transport,
            sessionIDGenerator: { sessionID }
        )

        XCTAssertThrowsError(try session.open()) {
            guard case .protocolViolation = $0 as? MTPCoreError else {
                return XCTFail("expected protocol violation, got \($0)")
            }
        }
        XCTAssertThrowsError(try session.open()) {
            XCTAssertEqual($0 as? MTPCoreError, .disconnected)
        }
    }

    func testTransactionIDNeverWrapsIntoOpenSessionZero() throws {
        let sessionID = try MTPSessionID(validating: 23)
        let transport = ScriptedMTPTransport(steps: [
            step(
                operation: .openSession,
                transactionID: 0,
                parameters: [sessionID.rawValue],
                containers: [response(.ok, transactionID: 0)]
            ),
            step(
                operation: .getDeviceInfo,
                transactionID: UInt32.max,
                containers: [
                    data(
                        .getDeviceInfo,
                        transactionID: UInt32.max,
                        payload: makeDeviceInfoPayload()
                    ),
                    response(.ok, transactionID: UInt32.max),
                ]
            ),
        ])
        let session = MTPDeviceSession(
            transport: transport,
            sessionIDGenerator: { sessionID },
            firstTransactionID: UInt32.max
        )

        try session.open()
        XCTAssertEqual(try session.getDeviceInfo().model, "Phone X")
        XCTAssertThrowsError(try session.getStorageIDs()) {
            guard case .protocolViolation = $0 as? MTPCoreError else {
                return XCTFail("expected transaction exhaustion, got \($0)")
            }
        }
        XCTAssertNoThrow(try transport.verifyConsumed())
    }
}

private extension MTPDeviceSessionTests {
    func step(
        operation: MTPOperationCode,
        transactionID: UInt32,
        parameters: [UInt32] = [],
        containers: [MTPContainer]
    ) -> ScriptedMTPTransport.Step {
        var payloadWriter = MTPBinaryWriter()
        parameters.forEach { payloadWriter.write($0) }
        let request = MTPContainer(
            type: .command,
            code: operation.rawValue,
            transactionID: try! MTPTransactionID(validating: transactionID),
            payload: payloadWriter.data
        )
        let bytes = containers.reduce(into: Data()) { partialResult, container in
            partialResult.append(try! container.encoded())
        }
        let split = max(1, min(7, bytes.count))
        return .init(
            expectedRequest: try! request.encoded(),
            result: .success([Data(bytes.prefix(split)), Data(bytes.dropFirst(split))])
        )
    }

    func data(
        _ operation: MTPOperationCode,
        transactionID: UInt32,
        payload: Data
    ) -> MTPContainer {
        MTPContainer(
            type: .data,
            code: operation.rawValue,
            transactionID: try! MTPTransactionID(validating: transactionID),
            payload: payload
        )
    }

    func response(
        _ code: MTPResponseCode,
        transactionID: UInt32
    ) -> MTPContainer {
        MTPContainer(
            type: .response,
            code: code.rawValue,
            transactionID: try! MTPTransactionID(validating: transactionID),
            payload: Data()
        )
    }

    func makeDeviceInfoPayload() -> Data {
        var writer = MTPBinaryWriter()
        writer.write(UInt16(100))
        writer.write(UInt32(6))
        writer.write(UInt16(101))
        try! writer.writeMTPString("microsoft.com: 1.0;")
        writer.write(UInt16(0))
        writeUInt16Array([], to: &writer)
        writeUInt16Array([], to: &writer)
        writeUInt16Array([], to: &writer)
        writeUInt16Array([], to: &writer)
        writeUInt16Array([], to: &writer)
        try! writer.writeMTPString("Acme")
        try! writer.writeMTPString("Phone X")
        try! writer.writeMTPString("1.0")
        try! writer.writeMTPString("serial")
        return writer.data
    }

    func makeStorageInfoPayload() -> Data {
        var writer = MTPBinaryWriter()
        writer.write(UInt16(3))
        writer.write(UInt16(2))
        writer.write(UInt16(0))
        writer.write(UInt64(1_000))
        writer.write(UInt64(500))
        writer.write(UInt32(4))
        try! writer.writeMTPString("Internal shared storage")
        try! writer.writeMTPString("Phone")
        return writer.data
    }

    func writeUInt16Array(_ values: [UInt16], to writer: inout MTPBinaryWriter) {
        writer.write(UInt32(values.count))
        values.forEach { writer.write($0) }
    }
}
