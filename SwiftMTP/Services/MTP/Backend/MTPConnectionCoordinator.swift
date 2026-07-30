import Foundation

/// Maps the app-facing UUID to one immutable provider + transport snapshot and
/// owns at most one open backend session.
nonisolated final class MTPConnectionCoordinator: @unchecked Sendable {
    typealias BackendFactory = () -> any MTPBackend

    private struct Registration {
        let snapshot: MTPDeviceSnapshot
        let providerKind: MTPProviderKind
    }

    private struct ActiveConnection {
        let appDeviceID: UUID
        let registration: Registration
        let backend: any MTPBackend
        let session: any MTPBackendSession
    }

    private let lock = NSLock()
    private let factories: [MTPProviderKind: BackendFactory]
    private var registrations: [UUID: Registration] = [:]
    private var active: ActiveConnection?

    init(factories: [MTPProviderKind: BackendFactory]) {
        self.factories = factories
    }

    deinit {
        close()
    }

    func register(
        appDeviceID: UUID,
        snapshot: MTPDeviceSnapshot,
        providerKind: MTPProviderKind
    ) throws {
        try lock.withLock {
            if let active, active.appDeviceID == appDeviceID {
                guard active.registration.snapshot.deviceID == snapshot.deviceID,
                      active.registration.providerKind == providerKind else {
                    throw MTPCoreError.busy
                }
            }
            registrations[appDeviceID] = Registration(
                snapshot: snapshot,
                providerKind: providerKind
            )
        }
    }

    func selectDevice(_ appDeviceID: UUID) throws {
        try lock.withLock {
            guard let registration = registrations[appDeviceID] else {
                throw MTPCoreError.noDevice
            }
            if let active,
               active.appDeviceID == appDeviceID,
               active.registration.snapshot.deviceID == registration.snapshot.deviceID,
               active.registration.providerKind == registration.providerKind {
                return
            }

            closeActiveLocked()
            guard let factory = factories[registration.providerKind] else {
                throw MTPCoreError.unsupportedDevice
            }
            let backend = factory()
            do {
                try backend.initialize()
                let session = try backend.openSession(
                    for: registration.snapshot.deviceID
                )
                guard session.deviceID == registration.snapshot.deviceID,
                      session.providerKind == registration.providerKind else {
                    session.close()
                    throw MTPCoreError.protocolViolation(
                        "coordinator opened a different provider or device"
                    )
                }
                active = ActiveConnection(
                    appDeviceID: appDeviceID,
                    registration: registration,
                    backend: backend,
                    session: session
                )
            } catch {
                backend.shutdown()
                throw error
            }
        }
    }

    func refreshStorage(
        appDeviceID: UUID,
        deviceID: MTPDeviceID,
        storageID: MTPStorageID
    ) throws -> MTPStorage {
        try lock.withLock {
            try withActiveSessionLocked(
                appDeviceID: appDeviceID,
                deviceID: deviceID
            ) {
                try $0.refreshStorage(storageID)
            }
        }
    }

    func listObjects(
        appDeviceID: UUID,
        deviceID: MTPDeviceID,
        storageID: MTPStorageID,
        parentID: MTPObjectID
    ) throws -> MTPDirectoryListing {
        try lock.withLock {
            try withActiveSessionLocked(
                appDeviceID: appDeviceID,
                deviceID: deviceID
            ) {
                try $0.listObjects(storageID: storageID, parentID: parentID)
            }
        }
    }

    func createFolder(
        appDeviceID: UUID,
        deviceID: MTPDeviceID,
        storageID: MTPStorageID,
        parentID: MTPObjectID,
        name: String
    ) throws -> MTPObjectID {
        try lock.withLock {
            try withActiveSessionLocked(
                appDeviceID: appDeviceID,
                deviceID: deviceID
            ) {
                try $0.createFolder(storageID: storageID, parentID: parentID, name: name)
            }
        }
    }

    func deleteObject(
        appDeviceID: UUID,
        deviceID: MTPDeviceID,
        objectID: MTPObjectID
    ) throws {
        try lock.withLock {
            try withActiveSessionLocked(
                appDeviceID: appDeviceID,
                deviceID: deviceID
            ) {
                try $0.deleteObject(objectID)
            }
        }
    }

    func download(
        appDeviceID: UUID,
        deviceID: MTPDeviceID,
        request: MTPDownloadRequest,
        progress: @escaping MTPTransferProgress,
        cancellation: MTPCancellationToken
    ) throws {
        try lock.withLock {
            try withActiveSessionLocked(
                appDeviceID: appDeviceID,
                deviceID: deviceID
            ) {
                try $0.download(
                    request,
                    progress: progress,
                    cancellation: cancellation
                )
            }
        }
    }

    func upload(
        appDeviceID: UUID,
        deviceID: MTPDeviceID,
        request: MTPUploadRequest,
        progress: @escaping MTPTransferProgress,
        cancellation: MTPCancellationToken
    ) throws {
        try lock.withLock {
            try withActiveSessionLocked(
                appDeviceID: appDeviceID,
                deviceID: deviceID
            ) {
                try $0.upload(
                    request,
                    progress: progress,
                    cancellation: cancellation
                )
            }
        }
    }

    /// Serializes discovery with active session operations and exposes the
    /// selected snapshot so scanning never opens a competing MTP session.
    func withExclusiveScanAccess<T>(
        providerKind: MTPProviderKind,
        operation: ([MTPDeviceID: MTPDeviceSnapshot]) throws -> T
    ) rethrows -> T {
        try lock.withLock {
            let reusableSnapshots: [MTPDeviceID: MTPDeviceSnapshot]
            if let active,
               active.registration.providerKind == providerKind {
                let snapshot = active.registration.snapshot
                reusableSnapshots = [snapshot.deviceID: snapshot]
            } else {
                reusableSnapshots = [:]
            }
            return try operation(reusableSnapshots)
        }
    }

    func close() {
        lock.withLock {
            closeActiveLocked()
        }
    }

    private func sessionLocked(
        appDeviceID: UUID,
        deviceID: MTPDeviceID
    ) throws -> any MTPBackendSession {
        guard let active,
              active.appDeviceID == appDeviceID,
              active.registration.snapshot.deviceID == deviceID,
              active.session.deviceID == deviceID,
              active.session.providerKind == active.registration.providerKind else {
            throw MTPCoreError.disconnected
        }
        return active.session
    }

    private func withActiveSessionLocked<T>(
        appDeviceID: UUID,
        deviceID: MTPDeviceID,
        operation: (any MTPBackendSession) throws -> T
    ) throws -> T {
        let session = try sessionLocked(
            appDeviceID: appDeviceID,
            deviceID: deviceID
        )
        do {
            return try operation(session)
        } catch {
            if Self.isTerminalSessionError(error) {
                closeActiveLocked()
            }
            throw error
        }
    }

    private static func isTerminalSessionError(_ error: Error) -> Bool {
        guard let error = error as? MTPCoreError else {
            return true
        }
        switch error {
        case .noDevice, .disconnected, .timeout, .cancelled, .usb,
             .protocolViolation:
            return true
        case .response(let code):
            return code == .sessionNotOpen || code == .invalidTransactionID
        case .invalidIdentifier, .invalidInput, .busy, .permissionDenied,
             .unsupportedDevice, .localFileIO:
            return false
        }
    }

    private func closeActiveLocked() {
        guard let active else {
            return
        }
        active.session.close()
        active.backend.shutdown()
        self.active = nil
    }
}
