import Foundation

nonisolated final class KalamMTPKernelBoundary:
    GoMTPKernelBoundary,
    GoMTPSnapshotRecording,
    @unchecked Sendable
{
    private let lock = NSLock()
    private let fileSystemABI: KalamFileSystemABI
    private let transferABI: KalamTransferABI
    private var knownDevices: Set<MTPDeviceID> = []

    init(
        fileSystemABI: KalamFileSystemABI = .live,
        transferABI: KalamTransferABI = .live
    ) {
        self.fileSystemABI = fileSystemABI
        self.transferABI = transferABI
    }

    func initialize() {
        Kalam_Init()
    }

    func shutdown() {
        // The process-wide Kalam pool is retained while Go is the fallback.
    }

    func scanDevicesJSON() -> UnsafeMutablePointer<CChar>? {
        Kalam_ScanResult()
    }

    func freeString(_ pointer: UnsafeMutablePointer<CChar>) {
        Kalam_FreeString(pointer)
    }

    func recordSnapshots(_ snapshots: [MTPDeviceSnapshot]) {
        lock.withLock {
            knownDevices = Set(snapshots.map(\.deviceID))
        }
    }

    func openSession(for deviceID: MTPDeviceID) throws -> any MTPBackendSession {
        let isKnownDevice = lock.withLock { knownDevices.contains(deviceID) }
        guard isKnownDevice else {
            throw MTPCoreError.noDevice
        }
        let response: KalamOpenSessionDTO = try deviceID.rawValue.withCString { rawDeviceID in
            try decodeKalamResponse(
                fileSystemABI.open(UnsafeMutablePointer(mutating: rawDeviceID)),
                abi: fileSystemABI
            )
        }
        try validateKalamSuccess(response.ok, errorCode: response.error)
        guard let token = response.token, !token.isEmpty else {
            throw MTPCoreError.protocolViolation("Go open-session response omitted its token")
        }
        return KalamMTPBackendSession(
            deviceID: deviceID,
            token: token,
            fileSystemABI: fileSystemABI,
            transferABI: transferABI
        )
    }
}
