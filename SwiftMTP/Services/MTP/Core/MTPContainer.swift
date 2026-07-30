import Foundation

nonisolated struct MTPContainer: Equatable, Sendable {
    static let headerLength: UInt64 = 12

    let type: MTPContainerType
    let code: UInt16
    let transactionID: MTPTransactionID
    let payload: Data

    init(
        type: MTPContainerType,
        code: UInt16,
        transactionID: MTPTransactionID,
        payload: Data
    ) {
        self.type = type
        self.code = code
        self.transactionID = transactionID
        self.payload = payload
    }

    /// Computes the 32-bit on-wire length without allocating the payload.
    /// Exact wire length `0xFFFFFFFF` and the larger-payload sentinel share
    /// the same field value; callers retain the UInt64 payload length to
    /// distinguish those cases without allocating the payload.
    static func dataWireLength(payloadLength: UInt64) -> UInt32 {
        guard payloadLength <= UInt64(UInt32.max) - headerLength else {
            return UInt32.max
        }
        return UInt32(payloadLength + headerLength)
    }

    func encoded() throws -> Data {
        let payloadLength = UInt64(payload.count)
        guard payloadLength <= UInt64(UInt32.max) - Self.headerLength else {
            throw MTPCoreError.invalidInput("materialized MTP container exceeds UInt32 wire length")
        }

        var writer = MTPBinaryWriter()
        writer.write(UInt32(payloadLength + Self.headerLength))
        writer.write(type.rawValue)
        writer.write(code)
        writer.write(transactionID.rawValue)
        writer.write(payload)
        return writer.data
    }

    static func decode(_ data: Data) throws -> Self {
        var reader = MTPBinaryReader(data: data)
        let declaredLength = try reader.readUInt32()
        guard declaredLength >= UInt32(headerLength) else {
            throw MTPCoreError.protocolViolation("container length is shorter than its 12-byte header")
        }
        guard declaredLength != UInt32.max else {
            throw MTPCoreError.protocolViolation(
                "streaming sentinel container cannot be decoded as one materialized buffer"
            )
        }
        guard Int(declaredLength) == data.count else {
            throw MTPCoreError.protocolViolation(
                "container length \(declaredLength) does not match \(data.count) available bytes"
            )
        }
        let rawType = try reader.readUInt16()
        guard let type = MTPContainerType(rawValue: rawType) else {
            throw MTPCoreError.protocolViolation("unknown container type \(rawType)")
        }
        let code = try reader.readUInt16()
        let transactionID = try MTPTransactionID(validating: reader.readUInt32())
        let payload = try reader.readData(count: reader.remainingCount)
        return Self(type: type, code: code, transactionID: transactionID, payload: payload)
    }
}

/// A data-container header whose payload is supplied or consumed separately.
/// `payloadLength` preserves the semantic difference between the largest exact
/// payload and the same `0xFFFFFFFF` wire value used for an unknown stream.
nonisolated struct MTPStreamingDataHeader: Equatable, Sendable {
    let operationCode: MTPOperationCode
    let transactionID: MTPTransactionID
    let payloadLength: UInt64?

    func encoded() -> Data {
        var writer = MTPBinaryWriter()
        writer.write(payloadLength.map(MTPContainer.dataWireLength) ?? UInt32.max)
        writer.write(MTPContainerType.data.rawValue)
        writer.write(operationCode.rawValue)
        writer.write(transactionID.rawValue)
        return writer.data
    }

    static func decode(
        _ data: Data,
        expectedPayloadLength: UInt64?
    ) throws -> Self {
        guard data.count == Int(MTPContainer.headerLength) else {
            throw MTPCoreError.protocolViolation("streaming data header must be exactly 12 bytes")
        }
        var reader = MTPBinaryReader(data: data)
        let wireLength = try reader.readUInt32()
        guard wireLength >= UInt32(MTPContainer.headerLength) else {
            throw MTPCoreError.protocolViolation("streaming data length is shorter than its header")
        }
        let rawType = try reader.readUInt16()
        guard rawType == MTPContainerType.data.rawValue else {
            throw MTPCoreError.protocolViolation("expected streaming data before MTP response")
        }
        let operationCode = MTPOperationCode(rawValue: try reader.readUInt16())
        let transactionID = try MTPTransactionID(validating: reader.readUInt32())
        let payloadLength: UInt64?
        if wireLength == UInt32.max {
            payloadLength = expectedPayloadLength
        } else {
            payloadLength = UInt64(wireLength) - MTPContainer.headerLength
        }
        return Self(
            operationCode: operationCode,
            transactionID: transactionID,
            payloadLength: payloadLength
        )
    }
}

/// Incremental validator for a single streaming MTP data container.
nonisolated struct MTPStreamingDataDecoder: Sendable {
    private let operationCode: MTPOperationCode
    private let transactionID: MTPTransactionID
    private let expectedPayloadLength: UInt64?
    private var headerBytes = Data()
    private var header: MTPStreamingDataHeader?

    private(set) var receivedPayloadLength: UInt64 = 0
    private(set) var isComplete = false

    init(
        operationCode: MTPOperationCode,
        transactionID: MTPTransactionID,
        expectedPayloadLength: UInt64?
    ) {
        self.operationCode = operationCode
        self.transactionID = transactionID
        self.expectedPayloadLength = expectedPayloadLength
    }

    mutating func append(_ fragment: Data, packetEnded: Bool) throws -> [Data] {
        guard !isComplete else {
            throw MTPCoreError.protocolViolation("streaming data contains bytes after terminal")
        }

        var payload = fragment
        if header == nil {
            let missingHeaderBytes = Int(MTPContainer.headerLength) - headerBytes.count
            let consumed = min(missingHeaderBytes, payload.count)
            headerBytes.append(payload.prefix(consumed))
            payload.removeFirst(consumed)
            guard headerBytes.count == Int(MTPContainer.headerLength) else {
                if packetEnded && fragment.isEmpty {
                    throw MTPCoreError.protocolViolation("streaming data header is truncated")
                }
                return []
            }

            let decoded = try MTPStreamingDataHeader.decode(
                headerBytes,
                expectedPayloadLength: expectedPayloadLength
            )
            guard decoded.operationCode == operationCode else {
                throw MTPCoreError.protocolViolation("streaming data operation code mismatch")
            }
            guard decoded.transactionID == transactionID else {
                throw MTPCoreError.protocolViolation("streaming data transaction ID mismatch")
            }
            if let expectedPayloadLength,
               let declaredPayloadLength = decoded.payloadLength,
               declaredPayloadLength != expectedPayloadLength {
                throw MTPCoreError.protocolViolation("streaming data declared length mismatch")
            }
            header = decoded
        }

        let effectiveLength = expectedPayloadLength ?? header?.payloadLength
        let payloadCount = UInt64(payload.count)
        if let effectiveLength {
            guard payloadCount <= effectiveLength - min(receivedPayloadLength, effectiveLength) else {
                throw MTPCoreError.protocolViolation("streaming data payload overrun")
            }
        }
        receivedPayloadLength += payloadCount

        if let effectiveLength {
            if receivedPayloadLength == effectiveLength {
                isComplete = true
            } else if packetEnded {
                throw MTPCoreError.protocolViolation(
                    "streaming data payload ended before its declared length"
                )
            }
        } else if packetEnded {
            isComplete = true
        }

        return payload.isEmpty ? [] : [payload]
    }
}

nonisolated struct MTPContainerFramer: Sendable {
    private var buffer = Data()

    var bufferedByteCount: Int {
        buffer.count
    }

    mutating func append(_ fragment: Data) throws -> [MTPContainer] {
        buffer.append(fragment)
        var containers: [MTPContainer] = []

        while buffer.count >= Int(MTPContainer.headerLength) {
            var headerReader = MTPBinaryReader(data: buffer)
            let declaredLength = try headerReader.readUInt32()
            guard declaredLength >= UInt32(MTPContainer.headerLength) else {
                throw MTPCoreError.protocolViolation("fragmented container has invalid length")
            }
            guard declaredLength != UInt32.max else {
                throw MTPCoreError.protocolViolation("streaming sentinel requires transport streaming mode")
            }
            let length = Int(declaredLength)
            guard buffer.count >= length else {
                break
            }

            let bytes = Data(buffer.prefix(length))
            containers.append(try MTPContainer.decode(bytes))
            buffer.removeFirst(length)
        }

        return containers
    }
}
