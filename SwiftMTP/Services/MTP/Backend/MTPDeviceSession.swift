import Foundation
import OSLog

nonisolated final class MTPDeviceSession {
    private enum State {
        case idle
        case open
        case invalid
        case closed
    }

    private struct TransactionResult {
        let data: Data?
        let responseCode: MTPResponseCode
    }

    private let transport: any MTPTransport
    private let sessionIDGenerator: () throws -> MTPSessionID
    private let firstTransactionID: UInt32
    private let lock = NSLock()
    private var state = State.idle
    private var nextTransactionID: UInt32 = 0

    init(
        transport: any MTPTransport,
        sessionIDGenerator: @escaping () throws -> MTPSessionID = {
            try MTPSessionID(validating: UInt32.random(in: 1..<UInt32.max))
        },
        firstTransactionID: UInt32 = 1
    ) {
        self.transport = transport
        self.sessionIDGenerator = sessionIDGenerator
        self.firstTransactionID = firstTransactionID
    }

    deinit {
        close()
    }

    func open() throws {
        try lock.withLock {
            switch state {
            case .idle:
                break
            case .open:
                throw MTPCoreError.busy
            case .invalid, .closed:
                throw MTPCoreError.disconnected
            }
            do {
                let sessionID = try sessionIDGenerator()
                let first = try transact(
                    operation: .openSession,
                    transactionID: 0,
                    parameters: [sessionID.rawValue],
                    expectsData: false
                )

                if first.responseCode == .sessionAlreadyOpen {
                    let staleClose = try transact(
                        operation: .closeSession,
                        transactionID: 0,
                        parameters: [],
                        expectsData: false
                    )
                    guard staleClose.responseCode == .ok else {
                        throw MTPCoreError.response(code: staleClose.responseCode)
                    }
                    let retry = try transact(
                        operation: .openSession,
                        transactionID: 0,
                        parameters: [sessionID.rawValue],
                        expectsData: false
                    )
                    guard retry.responseCode == .ok else {
                        throw MTPCoreError.response(code: retry.responseCode)
                    }
                } else {
                    guard first.responseCode == .ok else {
                        throw MTPCoreError.response(code: first.responseCode)
                    }
                }

                nextTransactionID = firstTransactionID
                state = .open
                MTPLog.session.debug("Opened MTP session")
            } catch {
                state = .invalid
                throw error
            }
        }
    }

    func getDeviceInfo() throws -> MTPDeviceInfoDataset {
        try execute(operation: .getDeviceInfo, expectsData: true) {
            try MTPDeviceInfoDataset.decode($0)
        }
    }

    func getStorageIDs() throws -> [MTPStorageID] {
        try execute(operation: .getStorageIDs, expectsData: true) { data in
            try MTPUInt32Array.decode(data).values.map {
                try MTPStorageID(validating: $0)
            }
        }
    }

    func getStorageInfo(_ storageID: MTPStorageID) throws -> MTPStorageInfoDataset {
        try execute(
            operation: .getStorageInfo,
            parameters: [storageID.rawValue],
            expectsData: true
        ) {
            try MTPStorageInfoDataset.decode($0)
        }
    }

    func close() {
        lock.withLock {
            guard state == .open else {
                state = .closed
                return
            }
            guard let transactionID = try? consumeTransactionID() else {
                MTPLog.session.error("CloseSession skipped after transaction ID exhaustion")
                state = .closed
                return
            }
            do {
                let result = try transact(
                    operation: .closeSession,
                    transactionID: transactionID,
                    parameters: [],
                    expectsData: false
                )
                if result.responseCode != .ok {
                    MTPLog.session.error(
                        "CloseSession response: \(result.responseCode.rawValue, privacy: .public)"
                    )
                }
            } catch {
                MTPLog.session.error("CloseSession failed: \(String(describing: error), privacy: .public)")
            }
            state = .closed
        }
    }

    private func execute<T>(
        operation: MTPOperationCode,
        parameters: [UInt32] = [],
        expectsData: Bool,
        decode: (Data) throws -> T
    ) throws -> T {
        try lock.withLock {
            guard state == .open else {
                throw MTPCoreError.disconnected
            }
            do {
                let transactionID = try consumeTransactionID()
                let result = try transact(
                    operation: operation,
                    transactionID: transactionID,
                    parameters: parameters,
                    expectsData: expectsData
                )
                guard result.responseCode == .ok else {
                    throw MTPCoreError.response(code: result.responseCode)
                }
                guard let data = result.data else {
                    throw MTPCoreError.protocolViolation(
                        "operation \(operation.rawValue) returned no data container"
                    )
                }
                return try decode(data)
            } catch {
                state = .invalid
                throw error
            }
        }
    }

    private func consumeTransactionID() throws -> UInt32 {
        guard nextTransactionID != 0 else {
            throw MTPCoreError.protocolViolation(
                "transaction ID space exhausted; create a fresh MTP session"
            )
        }
        let current = nextTransactionID
        nextTransactionID = current == UInt32.max ? 0 : current + 1
        return current
    }

    private func transact(
        operation: MTPOperationCode,
        transactionID: UInt32,
        parameters: [UInt32],
        expectsData: Bool
    ) throws -> TransactionResult {
        var payload = MTPBinaryWriter()
        parameters.forEach { payload.write($0) }
        let typedTransactionID = try MTPTransactionID(validating: transactionID)
        let request = MTPContainer(
            type: .command,
            code: operation.rawValue,
            transactionID: typedTransactionID,
            payload: payload.data
        )
        let fragments = try transport.transact(
            request.encoded(),
            cancellation: MTPCancellationToken()
        )
        var framer = MTPContainerFramer()
        var containers: [MTPContainer] = []
        for fragment in fragments {
            containers.append(contentsOf: try framer.append(fragment))
        }
        guard framer.bufferedByteCount == 0 else {
            throw MTPCoreError.protocolViolation("transaction ended with a partial container")
        }

        var dataPayload: Data?
        var responseCode: MTPResponseCode?
        for container in containers {
            guard container.transactionID == typedTransactionID else {
                throw MTPCoreError.protocolViolation(
                    "response transaction ID \(container.transactionID.rawValue) "
                        + "does not match request \(transactionID)"
                )
            }
            switch container.type {
            case .data:
                guard expectsData, dataPayload == nil, responseCode == nil else {
                    throw MTPCoreError.protocolViolation("unexpected data container")
                }
                guard container.code == operation.rawValue else {
                    throw MTPCoreError.protocolViolation("data container operation mismatch")
                }
                dataPayload = container.payload
            case .response:
                guard responseCode == nil else {
                    throw MTPCoreError.protocolViolation("duplicate response container")
                }
                guard container.payload.count.isMultiple(of: MemoryLayout<UInt32>.size) else {
                    throw MTPCoreError.protocolViolation(
                        "response parameters are not UInt32-aligned"
                    )
                }
                responseCode = MTPResponseCode(rawValue: container.code)
            case .command, .event:
                throw MTPCoreError.protocolViolation("unexpected transaction container type")
            }
        }
        guard let responseCode else {
            throw MTPCoreError.protocolViolation("transaction returned no response container")
        }
        if expectsData, dataPayload == nil, responseCode == .ok {
            throw MTPCoreError.protocolViolation("successful transaction returned no data")
        }
        return TransactionResult(data: dataPayload, responseCode: responseCode)
    }
}
