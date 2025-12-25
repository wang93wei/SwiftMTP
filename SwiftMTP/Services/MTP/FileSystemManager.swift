//
//  FileSystemManager.swift
//  SwiftMTP
//
//  Manages file system operations on MTP devices
//

import Foundation

class FileSystemManager {
    static let shared = FileSystemManager()

    private var fileCache: [String: CacheEntry] = [:]
    private let cacheExpirationInterval: TimeInterval = 30.0

    private struct CacheEntry {
        let items: [FileItem]
        let timestamp: Date

        var isExpired: Bool {
            Date().timeIntervalSince(timestamp) > 30.0
        }
    }

    private struct KalamFile: Codable {
        let id: UInt32
        let parentId: UInt32
        let storageId: UInt32
        let name: String
        let size: UInt64
        let isFolder: Bool
        let modTime: Int64
    }

    private init() {}

    // MARK: - Public Methods

    func getFileList(for device: Device, parentId: UInt32 = 0xFFFFFFFF, storageId: UInt32 = 0xFFFFFFFF) -> [FileItem] {
        let cacheKey = "\(device.id)-\(storageId)-\(parentId)"

        if let cached = fileCache[cacheKey], !cached.isExpired {
            return cached.items
        }

        guard let jsonPtr = Kalam_ListFiles(storageId, parentId) else {
            print("FileSystemManager: Kalam_ListFiles returned null")
            return []
        }

        let jsonString = String(cString: jsonPtr)
        Kalam_FreeString(jsonPtr)

        guard let data = jsonString.data(using: .utf8) else {
            print("FileSystemManager: Failed to convert JSON string to data")
            return []
        }

        do {
            let kalamFiles = try JSONDecoder().decode([KalamFile].self, from: data)
            let items = kalamFiles.map { kFile -> FileItem in
                let modDate = kFile.modTime > 0 ? Date(timeIntervalSince1970: TimeInterval(kFile.modTime)) : nil
                let fileType: String
                if kFile.isFolder {
                    fileType = "folder"  // 使用标识符而不是本地化字符串
                } else {
                    fileType = (kFile.name as NSString).pathExtension.uppercased()
                }
                return FileItem(
                    objectId: kFile.id,
                    parentId: kFile.parentId,
                    storageId: kFile.storageId,
                    name: kFile.name,
                    path: kFile.name,
                    size: kFile.size,
                    modifiedDate: modDate,
                    isDirectory: kFile.isFolder,
                    fileType: fileType
                )
            }

            let entry = CacheEntry(items: items, timestamp: Date())
            fileCache[cacheKey] = entry
            return items
        } catch {
            print("FileSystemManager: Failed to decode files JSON: \(error)")
            return []
        }
    }

    func getRootFiles(for device: Device) -> [FileItem] {
        guard let storage = device.storageInfo.first else {
            return []
        }

        return getFileList(for: device, parentId: 0xFFFFFFFF, storageId: storage.storageId)
    }

    func getChildrenFiles(for device: Device, parent: FileItem) -> [FileItem] {
        return getFileList(for: device, parentId: parent.objectId, storageId: parent.storageId)
    }

    func clearCache() {
        fileCache.removeAll()
        print("FileSystemManager: Cleared all cache")
    }

    func forceClearCache() {
        fileCache.removeAll()
        print("FileSystemManager: Force cleared all cache")
    }

    func clearCache(for device: Device) {
        fileCache = fileCache.filter { !$0.key.hasPrefix("\(device.id)-") }
        print("FileSystemManager: Cleared cache for device \(device.id)")
    }

    private func isExpired(_ timestamp: Date) -> Bool {
        Date().timeIntervalSince(timestamp) > cacheExpirationInterval
    }

    // MARK: - Private Methods
}
