import Foundation
@testable import SwiftMTP

func scriptedMTPMetadataStep(
    operation: MTPOperationCode,
    tid: UInt32,
    parameters: [UInt32] = [],
    outboundPayload: Data? = nil,
    inboundPayload: Data? = nil,
    response: MTPContainer
) -> ScriptedMTPTransport.Step {
    let transactionID = try! MTPTransactionID(validating: tid)
    let outboundData = outboundPayload.map {
        try! MTPContainer(
            type: .data,
            code: operation.rawValue,
            transactionID: transactionID,
            payload: $0
        ).encoded()
    }
    var incoming = Data()
    if let inboundPayload {
        incoming.append(
            try! MTPContainer(
                type: .data,
                code: operation.rawValue,
                transactionID: transactionID,
                payload: inboundPayload
            ).encoded()
        )
    }
    incoming.append(try! response.encoded())
    return ScriptedMTPTransport.Step(
        expectedRequest: scriptedMTPCommand(
            operation: operation,
            tid: tid,
            parameters: parameters
        ),
        expectedOutboundData: outboundData,
        result: .success([incoming])
    )
}

func scriptedMTPCommand(
    operation: MTPOperationCode,
    tid: UInt32,
    parameters: [UInt32] = []
) -> Data {
    var writer = MTPBinaryWriter()
    parameters.forEach { writer.write($0) }
    return try! MTPContainer(
        type: .command,
        code: operation.rawValue,
        transactionID: try! MTPTransactionID(validating: tid),
        payload: writer.data
    ).encoded()
}

func scriptedMTPResponse(
    _ code: MTPResponseCode,
    tid: UInt32,
    parameters: [UInt32] = []
) -> MTPContainer {
    var writer = MTPBinaryWriter()
    parameters.forEach { writer.write($0) }
    return MTPContainer(
        type: .response,
        code: code.rawValue,
        transactionID: try! MTPTransactionID(validating: tid),
        payload: writer.data
    )
}
