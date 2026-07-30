import Foundation

nonisolated struct MTPFileSystemDestination {
    let storageID: MTPStorageID
    let parentID: MTPObjectID
}

nonisolated enum FileSystemDestinationResolver {
    static func resolve(
        device: Device,
        parent: FileItem?
    ) throws -> MTPFileSystemDestination {
        if let parent {
            return MTPFileSystemDestination(
                storageID: parent.storageID,
                parentID: parent.objectID
            )
        }
        guard let storage = device.storageInfo.first else {
            throw MTPCoreError.invalidInput("device has no writable storage")
        }
        return MTPFileSystemDestination(storageID: storage.storageID, parentID: .root)
    }
}

nonisolated enum FileSystemObjectMapper {
    static func map(_ object: MTPObject) -> FileItem {
        let fileType: String
        if object.isFolder {
            fileType = "folder"
        } else {
            fileType = asciiUppercase((object.name as NSString).pathExtension)
        }
        return FileItem(
            objectID: object.id,
            parentID: object.parentID,
            storageID: object.storageID,
            name: object.name,
            path: object.name,
            size: object.size,
            modifiedDate: object.modificationDate,
            isDirectory: object.isFolder,
            fileType: fileType
        )
    }

    private static func asciiUppercase(_ value: String) -> String {
        String(value.map { character in
            guard let ascii = character.asciiValue, ascii >= 97, ascii <= 122 else {
                return character
            }
            return Character(UnicodeScalar(ascii - 32))
        })
    }
}
