import Foundation

nonisolated final class MTPDirectoryUploadFolderRouter {
    private let coordinator: any MTPTransferCoordinating
    private let request: MTPDirectoryUploadRequest
    private let cancellation: MTPCancellationToken
    private var folderCache: [String: MTPObjectID] = [:]

    private(set) var remoteMutationOccurred = false

    init(
        coordinator: any MTPTransferCoordinating,
        request: MTPDirectoryUploadRequest,
        cancellation: MTPCancellationToken
    ) {
        self.coordinator = coordinator
        self.request = request
        self.cancellation = cancellation
    }

    func resolveRoot(named name: String) throws -> MTPObjectID {
        try resolveFolder(name: name, path: "", parentID: request.parentID)
    }

    func resolveParent(
        for entry: MTPDirectoryUploadManifest.Entry,
        rootID: MTPObjectID
    ) throws -> MTPObjectID {
        guard !entry.folderPath.isEmpty else {
            return rootID
        }
        var parentID = rootID
        var currentPath = ""
        for component in entry.folderPath.split(separator: "/").map(String.init) {
            try cancellation.throwIfCancelled()
            currentPath = currentPath.isEmpty
                ? component
                : "\(currentPath)/\(component)"
            parentID = try resolveFolder(
                name: component,
                path: currentPath,
                parentID: parentID
            )
        }
        return parentID
    }

    private func resolveFolder(
        name: String,
        path: String,
        parentID: MTPObjectID
    ) throws -> MTPObjectID {
        if let cached = folderCache[path] {
            return cached
        }
        let listing = try coordinator.listObjects(
            appDeviceID: request.appDeviceID,
            deviceID: request.deviceIdentity.deviceID,
            storageID: request.storageID,
            parentID: parentID,
            cancellation: cancellation
        )
        if let existing = listing.objects.first(where: {
            $0.isFolder && $0.name == name
        }) {
            folderCache[path] = existing.id
            return existing.id
        }

        // Folder creation is mutation-ambiguous once submitted.
        remoteMutationOccurred = true
        let created = try coordinator.createFolder(
            appDeviceID: request.appDeviceID,
            deviceID: request.deviceIdentity.deviceID,
            storageID: request.storageID,
            parentID: parentID,
            name: name,
            cancellation: cancellation
        )
        folderCache[path] = created
        return created
    }
}
