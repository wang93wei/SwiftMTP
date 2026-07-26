import Foundation

/// Blocking MTP transaction transport backed by libusb asynchronous bulk
/// transfers. The surrounding session queue serializes command transactions.
nonisolated final class LibUSBTransport: MTPTransport {
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
}
