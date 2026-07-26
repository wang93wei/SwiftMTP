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
