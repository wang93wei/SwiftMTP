import Foundation
@testable import SwiftMTP

final class ScriptedMTPTransport: MTPTransport {
    struct Step {
        let expectedRequest: Data
        let expectedOutboundData: Data?
        let result: Result<[Data], MTPCoreError>

        init(
            expectedRequest: Data,
            expectedOutboundData: Data? = nil,
            result: Result<[Data], MTPCoreError>
        ) {
            self.expectedRequest = expectedRequest
            self.expectedOutboundData = expectedOutboundData
            self.result = result
        }
    }

    struct ReceiveStep {
        let expectedRequest: Data
        let expectedOperationCode: MTPOperationCode
        let expectedTransactionID: MTPTransactionID
        let expectedPayloadLength: UInt64?
        let chunks: [Data]
        let result: Result<MTPStreamingTransactionResult, MTPCoreError>
    }

    struct SendStep {
        let expectedRequest: Data
        let expectedDataHeader: MTPStreamingDataHeader
        let expectedSourceLength: UInt64?
        let expectedChunks: [Data]?
        let maximumReadLength: Int
        let beforeRead: (() -> Void)?
        let result: Result<MTPStreamingTransactionResult, MTPCoreError>

        init(
            expectedRequest: Data,
            expectedDataHeader: MTPStreamingDataHeader,
            expectedSourceLength: UInt64?,
            expectedChunks: [Data]? = nil,
            maximumReadLength: Int = 16 * 1024,
            beforeRead: (() -> Void)? = nil,
            result: Result<MTPStreamingTransactionResult, MTPCoreError>
        ) {
            self.expectedRequest = expectedRequest
            self.expectedDataHeader = expectedDataHeader
            self.expectedSourceLength = expectedSourceLength
            self.expectedChunks = expectedChunks
            self.maximumReadLength = maximumReadLength
            self.beforeRead = beforeRead
            self.result = result
        }
    }

    private var steps: [Step]
    private var receiveSteps: [ReceiveStep]
    private var sendSteps: [SendStep]
    private var sendResults: [Result<MTPStreamingTransactionResult, MTPCoreError>]

    init(
        steps: [Step],
        receiveSteps: [ReceiveStep] = [],
        sendSteps: [SendStep] = [],
        sendResults: [Result<MTPStreamingTransactionResult, MTPCoreError>] = []
    ) {
        self.steps = steps
        self.receiveSteps = receiveSteps
        self.sendSteps = sendSteps
        self.sendResults = sendResults
    }

    func transact(
        _ request: Data,
        outboundData: Data?,
        cancellation: MTPCancellationToken
    ) throws -> [Data] {
        try cancellation.throwIfCancelled()
        guard !steps.isEmpty else {
            throw MTPCoreError.protocolViolation("unexpected scripted transport request")
        }
        let step = steps[0]
        guard step.expectedRequest == request else {
            throw MTPCoreError.protocolViolation("scripted transport request mismatch")
        }
        guard step.expectedOutboundData == outboundData else {
            throw MTPCoreError.protocolViolation("scripted transport outbound data mismatch")
        }
        steps.removeFirst()
        return try step.result.get()
    }

    func receive(
        _ request: Data,
        operationCode: MTPOperationCode,
        transactionID: MTPTransactionID,
        expectedPayloadLength: UInt64?,
        sink: any MTPStreamSink,
        cancellation: MTPCancellationToken
    ) throws -> MTPStreamingTransactionResult {
        try cancellation.throwIfCancelled()
        guard !receiveSteps.isEmpty else {
            throw MTPCoreError.protocolViolation("unexpected scripted streaming receive")
        }
        let step = receiveSteps.removeFirst()
        guard step.expectedRequest == request,
              step.expectedOperationCode == operationCode,
              step.expectedTransactionID == transactionID,
              step.expectedPayloadLength == expectedPayloadLength else {
            throw MTPCoreError.protocolViolation("scripted streaming receive mismatch")
        }
        for chunk in step.chunks {
            try cancellation.throwIfCancelled()
            try sink.write(chunk)
        }
        return try step.result.get()
    }

    func send(
        _ request: Data,
        dataHeader: MTPStreamingDataHeader,
        source: any MTPStreamSource,
        cancellation: MTPCancellationToken
    ) throws -> MTPStreamingTransactionResult {
        try cancellation.throwIfCancelled()
        if !sendSteps.isEmpty {
            let step = sendSteps.removeFirst()
            guard step.expectedRequest == request,
                  step.expectedDataHeader == dataHeader,
                  step.expectedSourceLength == source.length else {
                throw MTPCoreError.protocolViolation("scripted streaming send mismatch")
            }
            step.beforeRead?()
            if let expectedChunks = step.expectedChunks {
                var chunks: [Data] = []
                while true {
                    try cancellation.throwIfCancelled()
                    let chunk = try source.read(maximumLength: step.maximumReadLength)
                    if chunk.isEmpty {
                        break
                    }
                    chunks.append(chunk)
                }
                guard chunks == expectedChunks else {
                    throw MTPCoreError.protocolViolation(
                        "scripted streaming source chunks mismatch"
                    )
                }
            }
            return try step.result.get()
        }
        guard !sendResults.isEmpty else {
            throw MTPCoreError.protocolViolation("unexpected scripted streaming send")
        }
        while true {
            let chunk = try source.read(maximumLength: 16 * 1024)
            if chunk.isEmpty {
                break
            }
            try cancellation.throwIfCancelled()
        }
        return try sendResults.removeFirst().get()
    }

    func verifyConsumed() throws {
        let remainingCount = steps.count + receiveSteps.count
            + sendSteps.count + sendResults.count
        guard remainingCount == 0 else {
            throw MTPCoreError.protocolViolation(
                "\(remainingCount) scripted transport steps remain"
            )
        }
    }
}
