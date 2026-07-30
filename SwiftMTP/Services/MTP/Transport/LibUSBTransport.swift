import Foundation

/// Blocking MTP transaction transport backed by libusb asynchronous bulk
/// transfers. The surrounding session queue serializes command transactions.
nonisolated final class LibUSBTransport: MTPTransport, @unchecked Sendable {
    private let handle: LibUSBDeviceHandle
    private let functions: LibUSBFunctionTable
    private let timeoutMilliseconds: UInt32
    private let readCapacity: Int
    private let transactionLock = NSLock()

    init(
        handle: LibUSBDeviceHandle,
        functions: LibUSBFunctionTable = LibUSBFunctionTable(),
        timeoutMilliseconds: UInt32 = 30_000,
        readCapacity: Int = 16 * 1024
    ) {
        self.handle = handle
        self.functions = functions
        self.timeoutMilliseconds = timeoutMilliseconds
        self.readCapacity = readCapacity
    }

    func transact(
        _ request: Data,
        outboundData: Data?,
        cancellation: MTPCancellationToken
    ) throws -> [Data] {
        try transactionLock.withLock {
            try cancellation.throwIfCancelled()
            guard !request.isEmpty else {
                throw MTPCoreError.invalidInput("MTP command must not be empty")
            }
            guard readCapacity >= Int(MTPContainer.headerLength) else {
                throw MTPCoreError.invalidInput("libusb read capacity is smaller than MTP header")
            }
            let write = LibUSBTransfer(
                handle: handle,
                endpoint: handle.interface.bulkOutEndpoint.address,
                buffer: .output(request),
                timeoutMilliseconds: timeoutMilliseconds,
                functions: functions
            )
            let written = try write.execute(cancellation: cancellation)
            guard written.count == request.count else {
                throw MTPCoreError.protocolViolation(
                    "short USB command write: \(written.count) of \(request.count) bytes"
                )
            }
            if let outboundData {
                let dataWrite = LibUSBTransfer(
                    handle: handle,
                    endpoint: handle.interface.bulkOutEndpoint.address,
                    buffer: .output(outboundData),
                    timeoutMilliseconds: timeoutMilliseconds,
                    functions: functions
                )
                let dataWritten = try dataWrite.execute(cancellation: cancellation)
                guard dataWritten.count == outboundData.count else {
                    throw MTPCoreError.protocolViolation(
                        "short USB metadata write: \(dataWritten.count) of \(outboundData.count) bytes"
                    )
                }
            }

            var fragments: [Data] = []
            var framer = MTPContainerFramer()
            var zeroLengthPacketCount = 0
            while true {
                let read = LibUSBTransfer(
                    handle: handle,
                    endpoint: handle.interface.bulkInEndpoint.address,
                    buffer: .input(capacity: readCapacity),
                    timeoutMilliseconds: timeoutMilliseconds,
                    functions: functions
                )
                let fragment = try read.execute(cancellation: cancellation)
                fragments.append(fragment)

                if fragment.isEmpty {
                    zeroLengthPacketCount += 1
                    guard zeroLengthPacketCount <= 3 else {
                        throw MTPCoreError.protocolViolation(
                            "transaction produced repeated zero-length packets without a response"
                        )
                    }
                    continue
                }
                zeroLengthPacketCount = 0

                let containers = try framer.append(fragment)
                if containers.contains(where: { $0.type == .response }) {
                    guard framer.bufferedByteCount == 0 else {
                        throw MTPCoreError.protocolViolation(
                            "response packet ended with a partial MTP container"
                        )
                    }
                    return fragments
                }
            }
        }
    }

    func receive(
        _ request: Data,
        operationCode: MTPOperationCode,
        transactionID: MTPTransactionID,
        expectedPayloadLength: UInt64?,
        sink: any MTPStreamSink,
        cancellation: MTPCancellationToken
    ) throws -> MTPStreamingTransactionResult {
        try transactionLock.withLock {
            try validateRequest(request, cancellation: cancellation)
            try write(request, label: "command", cancellation: cancellation)

            var decoder = MTPStreamingDataDecoder(
                operationCode: operationCode,
                transactionID: transactionID,
                expectedPayloadLength: expectedPayloadLength
            )
            while !decoder.isComplete {
                let fragment = try read(cancellation: cancellation)
                let chunks = try decoder.append(
                    fragment,
                    packetEnded: fragment.isEmpty
                )
                for chunk in chunks {
                    try sink.write(chunk)
                }
            }

            let response = try readResponse(
                transactionID: transactionID,
                cancellation: cancellation
            )
            return MTPStreamingTransactionResult(
                responseCode: response.code,
                responseParameters: response.parameters,
                transferredByteCount: decoder.receivedPayloadLength
            )
        }
    }

    func send(
        _ request: Data,
        dataHeader: MTPStreamingDataHeader,
        source: any MTPStreamSource,
        cancellation: MTPCancellationToken
    ) throws -> MTPStreamingTransactionResult {
        try transactionLock.withLock {
            try validateRequest(request, cancellation: cancellation)
            if let headerLength = dataHeader.payloadLength,
               let sourceLength = source.length,
               headerLength != sourceLength {
                throw MTPCoreError.invalidInput("stream source length does not match data header")
            }
            try write(request, label: "command", cancellation: cancellation)
            let transferredByteCount: UInt64
            if let payloadLength = dataHeader.payloadLength {
                transferredByteCount = try writeExactStream(
                    source,
                    header: dataHeader.encoded(),
                    payloadLength: payloadLength,
                    cancellation: cancellation
                )
            } else {
                transferredByteCount = try writeUnknownStream(
                    source,
                    header: dataHeader.encoded(),
                    cancellation: cancellation
                )
                if let sourceLength = source.length,
                   transferredByteCount != sourceLength {
                    throw MTPCoreError.protocolViolation(
                        "stream source ended before its advertised length"
                    )
                }
            }

            let response = try readResponse(
                transactionID: dataHeader.transactionID,
                cancellation: cancellation
            )
            return MTPStreamingTransactionResult(
                responseCode: response.code,
                responseParameters: response.parameters,
                transferredByteCount: transferredByteCount
            )
        }
    }

    private func validateRequest(
        _ request: Data,
        cancellation: MTPCancellationToken
    ) throws {
        try cancellation.throwIfCancelled()
        guard !request.isEmpty else {
            throw MTPCoreError.invalidInput("MTP command must not be empty")
        }
        guard readCapacity >= Int(MTPContainer.headerLength) else {
            throw MTPCoreError.invalidInput("libusb read capacity is smaller than MTP header")
        }
    }

    private func write(
        _ data: Data,
        label: String,
        addZeroPacket: Bool = false,
        cancellation: MTPCancellationToken
    ) throws {
        let transfer = LibUSBTransfer(
            handle: handle,
            endpoint: handle.interface.bulkOutEndpoint.address,
            buffer: .output(data),
            addZeroPacket: addZeroPacket,
            timeoutMilliseconds: timeoutMilliseconds,
            functions: functions
        )
        let written = try transfer.execute(cancellation: cancellation)
        guard written.count == data.count else {
            throw MTPCoreError.protocolViolation(
                "short USB \(label) write: \(written.count) of \(data.count) bytes"
            )
        }
    }

    private func writeExactStream(
        _ source: any MTPStreamSource,
        header: Data,
        payloadLength: UInt64,
        cancellation: MTPCancellationToken
    ) throws -> UInt64 {
        if payloadLength == 0 {
            guard try source.read(maximumLength: 1).isEmpty else {
                throw MTPCoreError.protocolViolation("stream source payload overrun")
            }
            try write(
                header,
                label: "streaming data header",
                addZeroPacket: true,
                cancellation: cancellation
            )
            return 0
        }

        let packetSize = Int(handle.interface.bulkOutEndpoint.maxPacketSize)
        let firstPayloadCapacity = packetSize - header.count
        guard firstPayloadCapacity > 0 else {
            throw MTPCoreError.protocolViolation(
                "bulk-out packet is too small for the MTP data header"
            )
        }

        try cancellation.throwIfCancelled()
        let firstMaximumLength = Int(
            min(UInt64(firstPayloadCapacity), payloadLength)
        )
        let firstChunk = try readSourceChunk(
            source,
            maximumLength: firstMaximumLength
        )
        guard !firstChunk.isEmpty else {
            throw MTPCoreError.protocolViolation(
                "stream source ended before its declared length"
            )
        }
        var firstTransfer = header
        firstTransfer.append(firstChunk)
        var transferredByteCount = UInt64(firstChunk.count)
        try write(
            firstTransfer,
            label: "streaming data header and first packet",
            addZeroPacket: transferredByteCount == payloadLength,
            cancellation: cancellation
        )

        while transferredByteCount < payloadLength {
            try cancellation.throwIfCancelled()
            let remaining = payloadLength - transferredByteCount
            let maximumLength = Int(min(UInt64(readCapacity), remaining))
            let chunk = try readSourceChunk(source, maximumLength: maximumLength)
            guard !chunk.isEmpty else {
                throw MTPCoreError.protocolViolation(
                    "stream source ended before its declared length"
                )
            }
            transferredByteCount += UInt64(chunk.count)
            try write(
                chunk,
                label: "streaming data chunk",
                addZeroPacket: transferredByteCount == payloadLength,
                cancellation: cancellation
            )
        }
        guard try source.read(maximumLength: 1).isEmpty else {
            throw MTPCoreError.protocolViolation("stream source payload overrun")
        }
        return transferredByteCount
    }

    private func writeUnknownStream(
        _ source: any MTPStreamSource,
        header: Data,
        cancellation: MTPCancellationToken
    ) throws -> UInt64 {
        var pendingChunk = try readSourceChunk(source, maximumLength: readCapacity)
        if pendingChunk.isEmpty {
            try write(
                header,
                label: "streaming data header",
                addZeroPacket: true,
                cancellation: cancellation
            )
            return 0
        }

        try write(header, label: "streaming data header", cancellation: cancellation)
        var transferredByteCount: UInt64 = 0
        while true {
            try cancellation.throwIfCancelled()
            let nextChunk = try readSourceChunk(source, maximumLength: readCapacity)
            let isFinalChunk = nextChunk.isEmpty
            try write(
                pendingChunk,
                label: "streaming data chunk",
                addZeroPacket: isFinalChunk,
                cancellation: cancellation
            )
            transferredByteCount += UInt64(pendingChunk.count)
            if isFinalChunk {
                return transferredByteCount
            }
            pendingChunk = nextChunk
        }
    }

    private func readSourceChunk(
        _ source: any MTPStreamSource,
        maximumLength: Int
    ) throws -> Data {
        let chunk = try source.read(maximumLength: maximumLength)
        guard chunk.count <= maximumLength else {
            throw MTPCoreError.protocolViolation("stream source exceeded requested chunk size")
        }
        return chunk
    }

    private func read(cancellation: MTPCancellationToken) throws -> Data {
        let transfer = LibUSBTransfer(
            handle: handle,
            endpoint: handle.interface.bulkInEndpoint.address,
            buffer: .input(capacity: readCapacity),
            timeoutMilliseconds: timeoutMilliseconds,
            functions: functions
        )
        return try transfer.execute(cancellation: cancellation)
    }

    private func readResponse(
        transactionID: MTPTransactionID,
        cancellation: MTPCancellationToken
    ) throws -> (code: MTPResponseCode, parameters: [UInt32]) {
        var framer = MTPContainerFramer()
        var zeroLengthPacketCount = 0
        while true {
            let fragment = try read(cancellation: cancellation)
            if fragment.isEmpty {
                zeroLengthPacketCount += 1
                guard zeroLengthPacketCount <= 3 else {
                    throw MTPCoreError.protocolViolation(
                        "streaming transaction produced repeated zero-length response packets"
                    )
                }
                continue
            }
            zeroLengthPacketCount = 0
            let containers = try framer.append(fragment)
            guard containers.count <= 1 else {
                throw MTPCoreError.protocolViolation("streaming response contains extra containers")
            }
            guard let response = containers.first else {
                continue
            }
            guard response.type == .response else {
                throw MTPCoreError.protocolViolation("expected MTP response after streaming data")
            }
            guard response.transactionID == transactionID else {
                throw MTPCoreError.protocolViolation("streaming response transaction ID mismatch")
            }
            guard framer.bufferedByteCount == 0 else {
                throw MTPCoreError.protocolViolation("streaming response has trailing partial bytes")
            }
            guard response.payload.count.isMultiple(of: MemoryLayout<UInt32>.size) else {
                throw MTPCoreError.protocolViolation("streaming response parameters are misaligned")
            }
            var reader = MTPBinaryReader(data: response.payload)
            var parameters: [UInt32] = []
            while reader.remainingCount > 0 {
                parameters.append(try reader.readUInt32())
            }
            return (MTPResponseCode(rawValue: response.code), parameters)
        }
    }
}
