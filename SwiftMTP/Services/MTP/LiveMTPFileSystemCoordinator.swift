import Foundation

nonisolated protocol MTPFileSystemCoordinating: Sendable {
    func listObjects(
        appDeviceID: UUID,
        deviceID: MTPDeviceID,
        storageID: MTPStorageID,
        parentID: MTPObjectID
    ) async throws -> MTPDirectoryListing
    func createFolder(
        appDeviceID: UUID,
        deviceID: MTPDeviceID,
        storageID: MTPStorageID,
        parentID: MTPObjectID,
        name: String
    ) async throws -> MTPObjectID
    func deleteObject(
        appDeviceID: UUID,
        deviceID: MTPDeviceID,
        objectID: MTPObjectID
    ) async throws
    func refreshStorage(
        appDeviceID: UUID,
        deviceID: MTPDeviceID,
        storageID: MTPStorageID
    ) async throws -> MTPStorage
}

nonisolated final class LiveMTPFileSystemCoordinator:
    MTPFileSystemCoordinating,
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
        parentID: MTPObjectID
    ) async throws -> MTPDirectoryListing {
        try await Task.detached {
            try self.coordinator.listObjects(
                appDeviceID: appDeviceID,
                deviceID: deviceID,
                storageID: storageID,
                parentID: parentID
            )
        }.value
    }

    func createFolder(
        appDeviceID: UUID,
        deviceID: MTPDeviceID,
        storageID: MTPStorageID,
        parentID: MTPObjectID,
        name: String
    ) async throws -> MTPObjectID {
        try await Task.detached {
            try self.coordinator.createFolder(
                appDeviceID: appDeviceID,
                deviceID: deviceID,
                storageID: storageID,
                parentID: parentID,
                name: name
            )
        }.value
    }

    func deleteObject(
        appDeviceID: UUID,
        deviceID: MTPDeviceID,
        objectID: MTPObjectID
    ) async throws {
        try await Task.detached {
            try self.coordinator.deleteObject(
                appDeviceID: appDeviceID,
                deviceID: deviceID,
                objectID: objectID
            )
        }.value
    }

    func refreshStorage(
        appDeviceID: UUID,
        deviceID: MTPDeviceID,
        storageID: MTPStorageID
    ) async throws -> MTPStorage {
        try await Task.detached {
            try self.coordinator.refreshStorage(
                appDeviceID: appDeviceID,
                deviceID: deviceID,
                storageID: storageID
            )
        }.value
    }
}
