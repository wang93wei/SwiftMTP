import Foundation
import OSLog

/// Injected migration boundary around the existing Kalam C ABI.
/// Go remains available as a fallback until the Swift cutover is verified.
nonisolated protocol GoMTPKernelBoundary: AnyObject {
    func initialize()
    func shutdown()
    func scanDevicesJSON() -> UnsafeMutablePointer<CChar>?
    func freeString(_ pointer: UnsafeMutablePointer<CChar>)
    func openSession(for deviceID: MTPDeviceID) throws -> any MTPBackendSession
}

nonisolated protocol GoMTPSnapshotRecording: AnyObject {
    func recordSnapshots(_ snapshots: [MTPDeviceSnapshot])
}

nonisolated final class GoMTPBackend: MTPBackend {
    typealias DiagnosticReporter = @Sendable (String) -> Void

    private let kernel: any GoMTPKernelBoundary
    private let reportDiagnostic: DiagnosticReporter
    private let stateLock = NSLock()
    private var initialized = false

    init(
        kernel: any GoMTPKernelBoundary,
        reportDiagnostic: @escaping DiagnosticReporter = {
            MTPLog.session.error("\($0, privacy: .public)")
        }
    ) {
        self.kernel = kernel
        self.reportDiagnostic = reportDiagnostic
    }

    func initialize() throws {
        let shouldInitialize = stateLock.withLock {
            guard !initialized else {
                return false
            }
            initialized = true
            return true
        }
        if shouldInitialize {
            kernel.initialize()
        }
    }

    func scanDevices() throws -> MTPScanResult {
        guard let pointer = kernel.scanDevicesJSON() else {
            throw MTPCoreError.disconnected
        }
        // The Kalam allocation must be released on every decode path.
        defer { kernel.freeString(pointer) }

        let json = String(cString: pointer)
        guard let data = json.data(using: .utf8) else {
            throw MTPCoreError.protocolViolation("Go device JSON is not UTF-8")
        }
        do {
            let response = try JSONDecoder().decode(GoScanResponseDTO.self, from: data)
            try validateGoScanSuccess(response.ok, errorCode: response.error)
            let snapshots = try (response.devices ?? [])
                .map { try $0.snapshot() }
            let failures = try (response.failures ?? [])
                .map { try $0.failure() }
            (kernel as? any GoMTPSnapshotRecording)?.recordSnapshots(snapshots)
            return MTPScanResult(snapshots: snapshots, failures: failures)
        } catch let error as MTPCoreError {
            throw error
        } catch {
            reportDiagnostic(
                "Go device JSON decode failed: byteCount=\(data.count), "
                    + "errorType=\(String(reflecting: type(of: error)))"
            )
            throw MTPCoreError.protocolViolation("Go device JSON decode failed")
        }
    }

    func openSession(for deviceID: MTPDeviceID) throws -> any MTPBackendSession {
        guard deviceID.rawValue.hasPrefix("go:") else {
            throw MTPCoreError.invalidInput("device ID does not belong to Go provider")
        }
        let session = try kernel.openSession(for: deviceID)
        guard session.deviceID == deviceID, session.providerKind == .go else {
            session.close()
            throw MTPCoreError.protocolViolation("Go kernel opened a different device")
        }
        return session
    }

    func shutdown() {
        let shouldShutdown = stateLock.withLock {
            guard initialized else {
                return false
            }
            initialized = false
            return true
        }
        if shouldShutdown {
            kernel.shutdown()
        }
    }
}

private nonisolated func validateGoScanSuccess(
    _ ok: Bool,
    errorCode: String?
) throws {
    guard ok else {
        switch errorCode {
        case "disconnected", "shutting_down":
            throw MTPCoreError.disconnected
        default:
            throw MTPCoreError.response(code: .generalError)
        }
    }
}

private nonisolated struct GoScanResponseDTO: Decodable {
    let ok: Bool
    let devices: [GoDeviceDTO]?
    let failures: [GoScanFailureDTO]?
    let error: String?
}

private nonisolated struct GoScanFailureDTO: Decodable {
    let deviceId: String
    let storageId: UInt32?
    let stage: String
    let error: String

    func failure() throws -> MTPScanFailure {
        let deviceID = try MTPDeviceID(validating: deviceId)
        let storageID = try storageId.map { try MTPStorageID(validating: $0) }
        let typedStage: MTPScanFailure.Stage
        switch stage {
        case "device":
            guard storageID == nil else {
                throw MTPCoreError.protocolViolation(
                    "Go device scan failure unexpectedly included a storage ID"
                )
            }
            typedStage = .device
        case "storage":
            typedStage = .storage
        default:
            throw MTPCoreError.protocolViolation("Go scan failure has an unknown stage")
        }
        return MTPScanFailure(
            deviceID: deviceID,
            storageID: storageID,
            stage: typedStage,
            error: Self.coreError(error)
        )
    }

    private static func coreError(_ code: String) -> MTPCoreError {
        switch code {
        case "disconnected", "stale_token", "unknown_token", "shutting_down":
            return .disconnected
        case "timeout":
            return .timeout
        case "permission_denied":
            return .permissionDenied
        default:
            return .response(code: .generalError)
        }
    }
}

private nonisolated struct GoDeviceDTO: Decodable {
    let id: String
    let name: String
    let manufacturer: String
    let model: String
    let storage: [GoStorageDTO]

    func snapshot() throws -> MTPDeviceSnapshot {
        MTPDeviceSnapshot(
            deviceID: try MTPDeviceID(validating: id),
            name: name,
            manufacturer: manufacturer,
            model: model,
            storages: try storage.map { try $0.storage() }
        )
    }
}

nonisolated struct GoStorageDTO: Decodable {
    let id: UInt32
    let description: String
    let freeSpace: UInt64
    let maxCapacity: UInt64

    func storage() throws -> MTPStorage {
        MTPStorage(
            id: try MTPStorageID(validating: id),
            description: description,
            freeSpace: freeSpace,
            maxCapacity: maxCapacity
        )
    }
}
