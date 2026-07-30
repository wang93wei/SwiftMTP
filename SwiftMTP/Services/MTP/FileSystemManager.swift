import Foundation
import OSLog

actor FileSystemManager: FileSystemManaging {
    static let shared = FileSystemManager(
        coordinator: LiveMTPFileSystemCoordinator(
            coordinator: MTPProviderRuntime.shared.coordinator
        )
    )

    private let coordinator: any MTPFileSystemCoordinating
    private let now: @Sendable () -> Date
    private let cacheTTL: TimeInterval
    private var cacheStore = FileSystemCacheStore()

    init(
        coordinator: any MTPFileSystemCoordinating,
        cacheTTL: TimeInterval = AppConfiguration.cacheExpirationInterval,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.coordinator = coordinator
        self.cacheTTL = cacheTTL
        self.now = now
    }

    func getFileList(
        for device: Device,
        parentID: MTPObjectID,
        storageID: MTPStorageID
    ) async throws -> [FileItem] {
        let scope = cacheScope(for: device)
        let key = FileSystemCacheKey(
            scope: scope,
            storageID: storageID,
            parentID: parentID
        )
        if let items = cacheStore.cachedItems(for: key, at: now(), ttl: cacheTTL) {
            return items
        }

        let generation = cacheStore.generation(for: scope)
        let listing = try await coordinator.listObjects(
            appDeviceID: device.id,
            deviceID: device.mtpIdentity.deviceID,
            storageID: storageID,
            parentID: parentID
        )
        let items = listing.objects.map(FileSystemObjectMapper.map)
        guard cacheStore.store(
            items,
            for: key,
            timestamp: now(),
            expectedGeneration: generation
        ) else {
            return items
        }
        if !listing.failures.isEmpty {
            MTPLog.fileSystem.warning(
                "Directory listing completed with \(listing.failures.count, privacy: .public) object warnings"
            )
        }
        return items
    }

    func getRootFiles(for device: Device) async throws -> [FileItem] {
        guard let storage = device.storageInfo.first else {
            return []
        }
        return try await getFileList(
            for: device,
            parentID: .root,
            storageID: storage.storageID
        )
    }

    func getChildrenFiles(for device: Device, parent: FileItem) async throws -> [FileItem] {
        try await getFileList(
            for: device,
            parentID: parent.objectID,
            storageID: parent.storageID
        )
    }

    /// Compatibility seam for the legacy directory-upload implementation.
    /// New filesystem callers must use the typed overload above.
    func getFileList(
        for device: Device,
        parentId: UInt32,
        storageId: UInt32
    ) async throws -> [FileItem] {
        try await getFileList(
            for: device,
            parentID: try MTPObjectID(validating: parentId),
            storageID: try MTPStorageID(validating: storageId)
        )
    }

    @discardableResult
    func createFolder(
        for device: Device,
        parent: FileItem?,
        name: String
    ) async throws -> MTPObjectID {
        let destination = try FileSystemDestinationResolver.resolve(
            device: device,
            parent: parent
        )
        let objectID = try await coordinator.createFolder(
            appDeviceID: device.id,
            deviceID: device.mtpIdentity.deviceID,
            storageID: destination.storageID,
            parentID: destination.parentID,
            name: name
        )
        clearCache(for: device)
        return objectID
    }

    func deleteObject(for device: Device, objectID: MTPObjectID) async throws {
        do {
            try await coordinator.deleteObject(
                appDeviceID: device.id,
                deviceID: device.mtpIdentity.deviceID,
                objectID: objectID
            )
            clearCache(for: device)
        } catch {
            let coreError = Self.coreError(error)
            MTPLog.fileSystem.error(
                "Single delete failed for device \(device.mtpIdentity.deviceID.rawValue, privacy: .private(mask: .hash)), object=\(objectID.rawValue, privacy: .public), error=\(String(describing: coreError), privacy: .public)"
            )
            clearCache(for: device)
            throw coreError
        }
    }

    func deleteObjects(
        for device: Device,
        objectIDs: [MTPObjectID]
    ) async throws -> FileSystemBatchDeleteResult {
        var succeededObjectIDs: [MTPObjectID] = []
        var failures: [FileSystemDeleteFailure] = []
        for objectID in objectIDs {
            do {
                try await coordinator.deleteObject(
                    appDeviceID: device.id,
                    deviceID: device.mtpIdentity.deviceID,
                    objectID: objectID
                )
                succeededObjectIDs.append(objectID)
            } catch {
                let coreError = Self.coreError(error)
                if Self.isOperationWideDeleteFailure(coreError) {
                    if !succeededObjectIDs.isEmpty {
                        clearCache(for: device)
                    }
                    throw coreError
                }
                failures.append(
                    FileSystemDeleteFailure(objectID: objectID, error: coreError)
                )
                MTPLog.fileSystem.error(
                    "Batch delete failed for object \(objectID.rawValue, privacy: .public): \(String(describing: coreError), privacy: .public)"
                )
            }
        }
        if !succeededObjectIDs.isEmpty {
            clearCache(for: device)
        }
        return FileSystemBatchDeleteResult(
            succeededObjectIDs: succeededObjectIDs,
            failures: failures
        )
    }

    func refreshStorage(for device: Device, storageID: MTPStorageID) async throws -> MTPStorage {
        return try await coordinator.refreshStorage(
            appDeviceID: device.id,
            deviceID: device.mtpIdentity.deviceID,
            storageID: storageID
        )
    }

    func clearCache() {
        cacheStore.invalidateAll()
    }

    func clearCache(for device: Device) {
        cacheStore.invalidate(cacheScope(for: device))
    }

    private func cacheScope(for device: Device) -> FileSystemCacheScope {
        FileSystemCacheScope(
            appDeviceID: device.id,
            identity: device.mtpIdentity
        )
    }

    private static func coreError(_ error: Error) -> MTPCoreError {
        error as? MTPCoreError
            ?? .protocolViolation("unexpected filesystem deletion failure")
    }

    private static func isOperationWideDeleteFailure(_ error: MTPCoreError) -> Bool {
        switch error {
        case .response(code: .sessionNotOpen), .response(code: .invalidTransactionID):
            return true
        case .response, .localFileIO:
            return false
        case .invalidIdentifier, .invalidInput, .noDevice, .busy, .permissionDenied,
             .disconnected, .timeout, .cancelled, .usb, .protocolViolation,
             .unsupportedDevice:
            return true
        }
    }
}
