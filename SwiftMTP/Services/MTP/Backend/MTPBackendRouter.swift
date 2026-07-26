import Foundation

nonisolated final class MTPBackendRouter {
    typealias Factory = () -> any MTPBackend

    private let lock = NSLock()
    private let factories: [MTPProviderKind: Factory]
    private var selectedProvider: MTPProviderKind
    private var hasOpenSession = false

    init(
        initialProvider: MTPProviderKind = .go,
        factories: [MTPProviderKind: Factory]
    ) {
        self.selectedProvider = initialProvider
        self.factories = factories
    }

    func selectProvider(_ provider: MTPProviderKind) throws {
        try lock.withLock {
            guard !hasOpenSession else {
                throw MTPCoreError.busy
            }
            guard factories[provider] != nil else {
                throw MTPCoreError.unsupportedDevice
            }
            selectedProvider = provider
        }
    }

    func openSession(for deviceID: MTPDeviceID) throws -> any MTPBackendSession {
        let selection: (MTPProviderKind, Factory) = try lock.withLock {
            guard !hasOpenSession else {
                throw MTPCoreError.busy
            }
            guard let factory = factories[selectedProvider] else {
                throw MTPCoreError.unsupportedDevice
            }
            hasOpenSession = true
            return (selectedProvider, factory)
        }

        let backend = selection.1()
        do {
            try backend.initialize()
            let session = try backend.openSession(for: deviceID)
            guard session.providerKind == selection.0, session.deviceID == deviceID else {
                session.close()
                throw MTPCoreError.protocolViolation(
                    "backend returned a session for a different provider or device"
                )
            }
            return RoutedMTPBackendSession(
                underlying: session,
                onClose: { [weak self] in
                    backend.shutdown()
                    self?.sessionDidClose()
                }
            )
        } catch {
            backend.shutdown()
            sessionDidClose()
            throw error
        }
    }

    private func sessionDidClose() {
        lock.withLock {
            hasOpenSession = false
        }
    }
}

private nonisolated final class RoutedMTPBackendSession: MTPBackendSession {
    private let underlying: any MTPBackendSession
    private let closeLock = NSLock()
    private var closed = false
    private let onClose: () -> Void

    var deviceID: MTPDeviceID { underlying.deviceID }
    var providerKind: MTPProviderKind { underlying.providerKind }

    init(underlying: any MTPBackendSession, onClose: @escaping () -> Void) {
        self.underlying = underlying
        self.onClose = onClose
    }

    deinit {
        close()
    }

    func listObjects(
        storageID: MTPStorageID,
        parentID: MTPObjectID
    ) throws -> [MTPObject] {
        try withOpenSession {
            try underlying.listObjects(storageID: storageID, parentID: parentID)
        }
    }

    func createFolder(
        storageID: MTPStorageID,
        parentID: MTPObjectID,
        name: String
    ) throws -> MTPObjectID {
        try withOpenSession {
            try underlying.createFolder(storageID: storageID, parentID: parentID, name: name)
        }
    }

    func deleteObject(_ objectID: MTPObjectID) throws {
        try withOpenSession {
            try underlying.deleteObject(objectID)
        }
    }

    func download(
        _ request: MTPDownloadRequest,
        progress: @escaping (UInt64) -> Void,
        cancellation: MTPCancellationToken
    ) throws {
        try withOpenSession {
            try underlying.download(request, progress: progress, cancellation: cancellation)
        }
    }

    func upload(
        _ request: MTPUploadRequest,
        progress: @escaping (UInt64) -> Void,
        cancellation: MTPCancellationToken
    ) throws {
        try withOpenSession {
            try underlying.upload(request, progress: progress, cancellation: cancellation)
        }
    }

    func refreshStorage(_ storageID: MTPStorageID) throws {
        try withOpenSession {
            try underlying.refreshStorage(storageID)
        }
    }

    func close() {
        let shouldNotify = closeLock.withLock {
            guard !closed else {
                return false
            }
            closed = true
            underlying.close()
            return true
        }
        guard shouldNotify else {
            return
        }
        onClose()
    }

    private func withOpenSession<T>(_ operation: () throws -> T) throws -> T {
        try closeLock.withLock {
            guard !closed else {
                throw MTPCoreError.disconnected
            }
            return try operation()
        }
    }
}
