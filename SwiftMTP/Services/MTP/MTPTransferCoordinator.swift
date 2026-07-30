import Foundation

/// Synchronous transfer seam used by the traditional queue-based manager.
nonisolated protocol MTPTransferCoordinating: AnyObject, Sendable {
    func listObjects(
        appDeviceID: UUID,
        deviceID: MTPDeviceID,
        storageID: MTPStorageID,
        parentID: MTPObjectID,
        cancellation: MTPCancellationToken
    ) throws -> MTPDirectoryListing

    func createFolder(
        appDeviceID: UUID,
        deviceID: MTPDeviceID,
        storageID: MTPStorageID,
        parentID: MTPObjectID,
        name: String,
        cancellation: MTPCancellationToken
    ) throws -> MTPObjectID

    func download(
        appDeviceID: UUID,
        deviceID: MTPDeviceID,
        request: MTPDownloadRequest,
        progress: @escaping MTPTransferProgress,
        cancellation: MTPCancellationToken
    ) throws

    func upload(
        appDeviceID: UUID,
        deviceID: MTPDeviceID,
        request: MTPUploadRequest,
        progress: @escaping MTPTransferProgress,
        cancellation: MTPCancellationToken
    ) throws
}

nonisolated extension MTPTransferCoordinating {
    func listObjects(
        appDeviceID: UUID,
        deviceID: MTPDeviceID,
        storageID: MTPStorageID,
        parentID: MTPObjectID,
        cancellation: MTPCancellationToken
    ) throws -> MTPDirectoryListing {
        throw MTPCoreError.unsupportedDevice
    }

    func createFolder(
        appDeviceID: UUID,
        deviceID: MTPDeviceID,
        storageID: MTPStorageID,
        parentID: MTPObjectID,
        name: String,
        cancellation: MTPCancellationToken
    ) throws -> MTPObjectID {
        throw MTPCoreError.unsupportedDevice
    }
}

nonisolated final class LiveMTPTransferCoordinator:
    MTPTransferCoordinating,
    @unchecked Sendable
{
    private let coordinator: MTPConnectionCoordinator

    init(coordinator: MTPConnectionCoordinator) {
        self.coordinator = coordinator
    }

    func listObjects(
        appDeviceID: UUID,
        deviceID: MTPDeviceID,
        storageID: MTPStorageID,
        parentID: MTPObjectID,
        cancellation: MTPCancellationToken
    ) throws -> MTPDirectoryListing {
        try cancellation.throwIfCancelled()
        let listing = try coordinator.listObjects(
            appDeviceID: appDeviceID,
            deviceID: deviceID,
            storageID: storageID,
            parentID: parentID
        )
        try cancellation.throwIfCancelled()
        return listing
    }

    func createFolder(
        appDeviceID: UUID,
        deviceID: MTPDeviceID,
        storageID: MTPStorageID,
        parentID: MTPObjectID,
        name: String,
        cancellation: MTPCancellationToken
    ) throws -> MTPObjectID {
        try cancellation.throwIfCancelled()
        let objectID = try coordinator.createFolder(
            appDeviceID: appDeviceID,
            deviceID: deviceID,
            storageID: storageID,
            parentID: parentID,
            name: name
        )
        try cancellation.throwIfCancelled()
        return objectID
    }

    func download(
        appDeviceID: UUID,
        deviceID: MTPDeviceID,
        request: MTPDownloadRequest,
        progress: @escaping MTPTransferProgress,
        cancellation: MTPCancellationToken
    ) throws {
        try coordinator.download(
            appDeviceID: appDeviceID,
            deviceID: deviceID,
            request: request,
            progress: progress,
            cancellation: cancellation
        )
    }

    func upload(
        appDeviceID: UUID,
        deviceID: MTPDeviceID,
        request: MTPUploadRequest,
        progress: @escaping MTPTransferProgress,
        cancellation: MTPCancellationToken
    ) throws {
        try coordinator.upload(
            appDeviceID: appDeviceID,
            deviceID: deviceID,
            request: request,
            progress: progress,
            cancellation: cancellation
        )
    }
}
