import Foundation

/// Maps the app-facing UUID to one immutable provider + transport snapshot and
/// owns at most one open backend session.
nonisolated final class MTPConnectionCoordinator {
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
    ) throws {
        try lock.withLock {
            let session = try sessionLocked(
                appDeviceID: appDeviceID,
                deviceID: deviceID
            )
            try session.refreshStorage(storageID)
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
              active.session.deviceID == deviceID else {
            throw MTPCoreError.disconnected
        }
        return active.session
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
