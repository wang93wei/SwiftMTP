//
//  FileSystemManager.swift  
//  SwiftMTP
//
//  Manages file system operations on MTP devices
//

import Foundation

class FileSystemManager {
    static let shared = FileSystemManager()
    
    private var fileCache: [String: [FileItem]] = [:]
    
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
        // Check cache first
        let cacheKey = "\(device.id)-\(storageId)-\(parentId)"
        if let cached = fileCache[cacheKey] {
            return cached
        }
        
        // Call Kalam Bridge
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
                return FileItem(
                    objectId: kFile.id,
                    parentId: kFile.parentId,
                    storageId: kFile.storageId,
                    name: kFile.name,
                    path: kFile.name,
                    size: kFile.size,
                    modifiedDate: modDate,
                    isDirectory: kFile.isFolder,
                    fileType: kFile.isFolder ? "文件夹" : (kFile.name as NSString).pathExtension.uppercased()
                )
            }
            
            // Cache the result
            fileCache[cacheKey] = items
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
        // More aggressive cache clearing
        fileCache.removeAll()
        print("FileSystemManager: Force cleared all cache")
    }
    
    func clearCache(for device: Device) {
        // Remove all cache entries for this device
        fileCache = fileCache.filter { !$0.key.hasPrefix("\(device.id)-") }
        print("FileSystemManager: Cleared cache for device \(device.id)")
    }
    
    // MARK: - Private Methods
    
    /*
    private func createFileItem(from file: LIBMTP_file_t) -> FileItem {
        let name = String(cString: file.filename)
        let size = file.filesize
        let objectId = file.item_id
        let parentId = file.parent_id
        let storageId = file.storage_id
        let isDirectory = file.filetype == LIBMTP_FILETYPE_FOLDER
        
        // Get file type description
        let fileTypePtr = LIBMTP_Get_Filetype_Description(LIBMTP_filetype_t(file.filetype.rawValue))
        let fileType = fileTypePtr != nil ? String(cString: fileTypePtr!) : "Unknown"
        
        // Convert modification time
        var modifiedDate: Date?
        if file.modificationdate > 0 {
            modifiedDate = Date(timeIntervalSince1970: TimeInterval(file.modificationdate))
        }
        
        // Build path
        let path = name // Simplified, could build full path if needed
        
        return FileItem(
            objectId: objectId,
            parentId: parentId,
            storageId: storageId,
            name: name,
            path: path,
            size: size,
            modifiedDate: modifiedDate,
            isDirectory: isDirectory,
            fileType: fileType
        )
    }
    */
}
