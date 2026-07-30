import Foundation
import OSLog

nonisolated enum MTPDataPhase: Equatable, Sendable {
    case none
    case inbound
    case outbound(Data)
}

nonisolated struct MTPTransactionResult: Equatable, Sendable {
    let data: Data?
    let responseCode: MTPResponseCode
    let responseParameters: [UInt32]
}

nonisolated struct MTPDownloadResult: Equatable, Sendable {
    let expectedByteCount: UInt64?
    let transferredByteCount: UInt64
}

nonisolated final class MTPDeviceSession {
    enum State {
        case idle
        case open
        case invalid
        case closed
    }

    let transport: any MTPTransport
    private let sessionIDGenerator: () throws -> MTPSessionID
    let reportUploadDiagnostic: MTPUploadDiagnosticReporter
    private let firstTransactionID: UInt32
    let lock = NSLock()
    var state = State.idle
    private var nextTransactionID: UInt32 = 0

    init(
        transport: any MTPTransport,
        sessionIDGenerator: @escaping () throws -> MTPSessionID = {
            try MTPSessionID(validating: UInt32.random(in: 1..<UInt32.max))
        },
        reportUploadDiagnostic: @escaping MTPUploadDiagnosticReporter = {
            MTPLog.session.error(
                "Upload compensation outcome for object \($0.objectID.rawValue, privacy: .public): \(String(describing: $0.outcome), privacy: .public)"
            )
        },
        firstTransactionID: UInt32 = 1
    ) {
        self.transport = transport
        self.sessionIDGenerator = sessionIDGenerator
        self.reportUploadDiagnostic = reportUploadDiagnostic
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
                    phase: .none
                )

                if first.responseCode == .sessionAlreadyOpen {
                    let staleClose = try transact(
                        operation: .closeSession,
                        transactionID: 0,
                        parameters: [],
                        phase: .none
                    )
                    guard staleClose.responseCode == .ok else {
                        throw MTPCoreError.response(code: staleClose.responseCode)
                    }
                    let retry = try transact(
                        operation: .openSession,
                        transactionID: 0,
                        parameters: [sessionID.rawValue],
                        phase: .none
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
        try executeInbound(operation: .getDeviceInfo) {
            try MTPDeviceInfoDataset.decode($0)
        }
    }

    func getStorageIDs() throws -> [MTPStorageID] {
        try executeInbound(operation: .getStorageIDs) { data in
            try MTPUInt32Array.decode(data).values.map {
                try MTPStorageID(validating: $0)
            }
        }
    }

    func getStorageInfo(_ storageID: MTPStorageID) throws -> MTPStorageInfoDataset {
        try executeInbound(
            operation: .getStorageInfo,
            parameters: [storageID.rawValue]
        ) {
            try MTPStorageInfoDataset.decode($0)
        }
    }

    func getObjectHandles(
        storageID: MTPStorageID,
        parentID: MTPObjectID
    ) throws -> [MTPObjectID] {
        try executeInbound(
            operation: .getObjectHandles,
            parameters: [storageID.rawValue, 0, parentID.rawValue]
        ) { data in
            try MTPUInt32Array.decode(data).values.map {
                try MTPObjectID(validating: $0)
            }
        }
    }

    func getObjectInfo(_ objectID: MTPObjectID) throws -> MTPObjectInfoDataset {
        try executeInbound(
            operation: .getObjectInfo,
            parameters: [objectID.rawValue]
        ) {
            try MTPObjectInfoDataset.decode($0)
        }
    }

    func createFolder(
        storageID: MTPStorageID,
        parentID: MTPObjectID,
        name: String
    ) throws -> MTPObjectID {
        let dataset = try MTPObjectInfoDataset.folder(
            storageID: storageID,
            parentObject: parentID,
            name: name
        )
        let result = try execute(
            operation: .sendObjectInfo,
            parameters: [storageID.rawValue, parentID.rawValue],
            phase: .outbound(try dataset.encoded())
        )
        guard result.responseParameters.count == 3 else {
            throw invalidateProtocol("SendObjectInfo response must contain three parameters")
        }
        guard result.responseParameters[0] == storageID.rawValue,
              result.responseParameters[1] == parentID.rawValue else {
            throw invalidateProtocol("SendObjectInfo response storage or parent mismatch")
        }
        guard result.responseParameters[2] != 0 else {
            throw invalidateProtocol("SendObjectInfo returned an invalid zero object handle")
        }
        return try MTPObjectID(validating: result.responseParameters[2])
    }

    func deleteObject(_ objectID: MTPObjectID) throws {
        _ = try execute(
            operation: .deleteObject,
            parameters: [objectID.rawValue, 0],
            phase: .none
        )
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
                    phase: .none
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

    private func executeInbound<T>(
        operation: MTPOperationCode,
        parameters: [UInt32] = [],
        decode: (Data) throws -> T
    ) throws -> T {
        let result = try execute(
            operation: operation,
            parameters: parameters,
            phase: .inbound
        )
        guard let data = result.data else {
            throw invalidateProtocol(
                "operation \(operation.rawValue) returned no data container"
            )
        }
        do {
            return try decode(data)
        } catch {
            // A successful inbound transaction whose payload cannot satisfy the
            // operation's wire schema is a protocol failure, even when the
            // low-level validator reports an invalid identifier.
            lock.withLock { state = .invalid }
            throw error
        }
    }

    func executeInboundLocked<T>(
        operation: MTPOperationCode,
        parameters: [UInt32] = [],
        cancellation: MTPCancellationToken,
        decode: (Data) throws -> T
    ) throws -> T {
        let result = try executeLocked(
            operation: operation,
            parameters: parameters,
            phase: .inbound,
            cancellation: cancellation
        )
        guard let data = result.data else {
            throw MTPCoreError.protocolViolation(
                "operation \(operation.rawValue) returned no data container"
            )
        }
        do {
            return try decode(data)
        } catch {
            state = .invalid
            throw error
        }
    }

    private func execute(
        operation: MTPOperationCode,
        parameters: [UInt32] = [],
        phase: MTPDataPhase
    ) throws -> MTPTransactionResult {
        try lock.withLock {
            guard state == .open else {
                throw MTPCoreError.disconnected
            }
            do {
                return try executeLocked(
                    operation: operation,
                    parameters: parameters,
                    phase: phase,
                    cancellation: MTPCancellationToken()
                )
            } catch {
                if shouldInvalidate(error) {
                    state = .invalid
                }
                throw error
            }
        }
    }

    func executeLocked(
        operation: MTPOperationCode,
        parameters: [UInt32],
        phase: MTPDataPhase,
        cancellation: MTPCancellationToken
    ) throws -> MTPTransactionResult {
        let transactionID = try consumeTransactionID()
        let result = try transact(
            operation: operation,
            transactionID: transactionID,
            parameters: parameters,
            phase: phase,
            cancellation: cancellation
        )
        guard result.responseCode == .ok else {
            throw MTPCoreError.response(code: result.responseCode)
        }
        return result
    }

    func consumeTransactionID() throws -> UInt32 {
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
        phase: MTPDataPhase,
        cancellation: MTPCancellationToken = MTPCancellationToken()
    ) throws -> MTPTransactionResult {
        let typedTransactionID = try MTPTransactionID(validating: transactionID)
        let request = try command(
            operation: operation,
            transactionID: typedTransactionID,
            parameters: parameters
        )
        let outboundContainer: Data?
        if case .outbound(let outboundPayload) = phase {
            outboundContainer = try MTPContainer(
                type: .data,
                code: operation.rawValue,
                transactionID: typedTransactionID,
                payload: outboundPayload
            ).encoded()
        } else {
            outboundContainer = nil
        }
        let fragments = try transport.transact(
            request,
            outboundData: outboundContainer,
            cancellation: cancellation
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
        var responseParameters: [UInt32] = []
        for container in containers {
            guard container.transactionID == typedTransactionID else {
                throw MTPCoreError.protocolViolation(
                    "response transaction ID \(container.transactionID.rawValue) "
                        + "does not match request \(transactionID)"
                )
            }
            switch container.type {
            case .data:
                guard phase == .inbound, dataPayload == nil, responseCode == nil else {
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
                var parameterReader = MTPBinaryReader(data: container.payload)
                while parameterReader.remainingCount > 0 {
                    responseParameters.append(try parameterReader.readUInt32())
                }
            case .command, .event:
                throw MTPCoreError.protocolViolation("unexpected transaction container type")
            }
        }
        guard let responseCode else {
            throw MTPCoreError.protocolViolation("transaction returned no response container")
        }
        if phase == .inbound, dataPayload == nil, responseCode == .ok {
            throw MTPCoreError.protocolViolation("successful transaction returned no data")
        }
        return MTPTransactionResult(
            data: dataPayload,
            responseCode: responseCode,
            responseParameters: responseParameters
        )
    }

    func command(
        operation: MTPOperationCode,
        transactionID: MTPTransactionID,
        parameters: [UInt32]
    ) throws -> Data {
        var payload = MTPBinaryWriter()
        parameters.forEach { payload.write($0) }
        return try MTPContainer(
            type: .command,
            code: operation.rawValue,
            transactionID: transactionID,
            payload: payload.data
        ).encoded()
    }

    private func invalidateProtocol(_ message: String) -> MTPCoreError {
        lock.withLock { state = .invalid }
        return .protocolViolation(message)
    }

    func shouldInvalidate(_ error: Error) -> Bool {
        guard let error = error as? MTPCoreError else {
            return true
        }
        switch error {
        case .protocolViolation, .disconnected, .timeout, .cancelled, .usb:
            return true
        case .response(let code):
            return code == .sessionNotOpen || code == .invalidTransactionID
        case .invalidIdentifier, .invalidInput, .noDevice, .busy,
             .permissionDenied, .unsupportedDevice, .localFileIO:
            return false
        }
    }

}
