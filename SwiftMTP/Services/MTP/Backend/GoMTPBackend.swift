import Foundation

/// Injected migration boundary around the existing Kalam C ABI.
/// Production managers are not wired to this adapter in the foundation phase.
nonisolated protocol GoMTPKernelBoundary: AnyObject {
    func initialize()
    func shutdown()
    func scanDevicesJSON() -> UnsafeMutablePointer<CChar>?
    func freeString(_ pointer: UnsafeMutablePointer<CChar>)
    func openSession(for deviceID: MTPDeviceID) throws -> any MTPBackendSession
}

nonisolated final class GoMTPBackend: MTPBackend {
    private let kernel: any GoMTPKernelBoundary
    private let stateLock = NSLock()
    private var initialized = false

    init(kernel: any GoMTPKernelBoundary) {
        self.kernel = kernel
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

    func scanDevices() throws -> [MTPDeviceSnapshot] {
        guard let pointer = kernel.scanDevicesJSON() else {
            throw MTPCoreError.noDevice
        }
        // The Kalam allocation must be released on every decode path.
        defer { kernel.freeString(pointer) }

        let json = String(cString: pointer)
        guard let data = json.data(using: .utf8) else {
            throw MTPCoreError.protocolViolation("Go device JSON is not UTF-8")
        }
        do {
            return try JSONDecoder()
                .decode([GoDeviceDTO].self, from: data)
                .map { try $0.snapshot() }
        } catch let error as MTPCoreError {
            throw error
        } catch {
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

private nonisolated struct GoDeviceDTO: Decodable {
    let id: Int
    let name: String
    let manufacturer: String
    let model: String
    let storage: [GoStorageDTO]

    func snapshot() throws -> MTPDeviceSnapshot {
        MTPDeviceSnapshot(
            deviceID: try MTPDeviceID(validating: "go:\(id)"),
            name: name,
            manufacturer: manufacturer,
            model: model,
            storages: try storage.map { try $0.storage() }
        )
    }
}

private nonisolated struct GoStorageDTO: Decodable {
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
