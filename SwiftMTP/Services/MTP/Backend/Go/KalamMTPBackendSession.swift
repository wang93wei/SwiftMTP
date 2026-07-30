import Foundation

nonisolated final class KalamMTPBackendSession: MTPBackendSession {
    let deviceID: MTPDeviceID
    let providerKind = MTPProviderKind.go

    private let lock = NSLock()
    private let token: String
    let fileSystemABI: KalamFileSystemABI
    let transferABI: KalamTransferABI
    private var closed = false

    init(
        deviceID: MTPDeviceID,
        token: String,
        fileSystemABI: KalamFileSystemABI,
        transferABI: KalamTransferABI
    ) {
        self.deviceID = deviceID
        self.token = token
        self.fileSystemABI = fileSystemABI
        self.transferABI = transferABI
    }

    func close() {
        lock.withLock {
            guard !closed else {
                return
            }
            closed = true
            _ = try? withTokenPointer { tokenPointer -> KalamMutationResponseDTO in
                try decodeKalamResponse(
                    fileSystemABI.close(tokenPointer),
                    abi: fileSystemABI
                )
            }
        }
    }

    func withOpenSession<T>(_ body: () throws -> T) throws -> T {
        try lock.withLock {
            guard !closed else {
                throw MTPCoreError.disconnected
            }
            return try body()
        }
    }

    func withTokenPointer<T>(
        _ body: (UnsafeMutablePointer<CChar>) throws -> T
    ) rethrows -> T {
        try token.withCString { pointer in
            try body(UnsafeMutablePointer(mutating: pointer))
        }
    }
}
