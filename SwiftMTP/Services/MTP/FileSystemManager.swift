//
//  FileSystemManager.swift
//  SwiftMTP
//
//  Manages file system operations on MTP devices
//

import Foundation

// MARK: - FileSystemManager

/// 文件系统管理器
/// 负责管理 MTP 设备上的文件系统操作，包括文件列表获取和缓存管理
class FileSystemManager {
    // MARK: - 单例
    
    /// 共享实例
    static let shared = FileSystemManager()
    
    // MARK: - 常量
    
    /// 缓存过期时间（秒）
    private static let CacheExpirationInterval: TimeInterval = 60.0
    
    /// 根目录 ID（MTP 协议标准值）
    private static let RootDirectoryId: UInt32 = 0xFFFFFFFF
    
    // MARK: - 属性
    
    // MARK: - 内部类型
    
    /// 缓存条目
    private struct CacheEntry {
        /// 文件列表
        let items: [FileItem]
        /// 缓存时间戳
        let timestamp: Date
        
        /// 判断缓存是否过期
        var isExpired: Bool {
            Date().timeIntervalSince(timestamp) > FileSystemManager.CacheExpirationInterval
        }
    }
    
    /// 缓存条目包装类（用于NSCache，因为NSCache要求对象类型必须是类）
    private class CacheEntryWrapper: NSObject {
        let entry: CacheEntry
        init(_ entry: CacheEntry) {
            self.entry = entry
        }
    }
    
    /// 文件缓存（使用NSCache实现自动内存管理）
    private let fileCache = NSCache<NSString, CacheEntryWrapper>()
    
    /// 设备ID到缓存键的映射（用于精确清理缓存）
    private var deviceCacheKeys: [UUID: Set<String>] = [:]
    private let cacheKeysLock = NSLock()
    
    /// Kalam 文件结构（用于 JSON 解码）
    private struct KalamFile: Codable {
        let id: UInt32
        let parentId: UInt32
        let storageId: UInt32
        let name: String
        let size: UInt64
        let isFolder: Bool
        let modTime: Int64
    }
    
    // MARK: - 初始化
    
    private init() {
        // 配置文件缓存
        fileCache.countLimit = 1000  // 最多缓存1000个目录
        fileCache.totalCostLimit = 50 * 1024 * 1024  // 50MB限制
    }
    
    // MARK: - 公共方法
    
    /// 获取指定目录的文件列表
    /// - Parameters:
    ///   - device: 目标设备
    ///   - parentId: 父目录 ID（默认为根目录）
    ///   - storageId: 存储设备 ID
    /// - Returns: 文件列表，如果获取失败则返回空数组
    func getFileList(for device: Device, parentId: UInt32 = RootDirectoryId, storageId: UInt32 = RootDirectoryId) -> [FileItem] {
        let cacheKey = "\(device.id)-\(storageId)-\(parentId)"
        
        // 检查缓存（NSCache是线程安全的）
        if let cachedWrapper = fileCache.object(forKey: NSString(string: cacheKey)), !cachedWrapper.entry.isExpired {
            return cachedWrapper.entry.items
        }
        
        // 调用 Kalam 获取文件列表
        guard let jsonPtr = Kalam_ListFiles(storageId, parentId) else {
            print("[FileSystemManager] Kalam_ListFiles returned null")
            return []
        }
        
        // 使用 defer 确保内存总是被释放
        defer {
            Kalam_FreeString(jsonPtr)
        }
        
        let jsonString = String(cString: jsonPtr)
        
        guard let data = jsonString.data(using: .utf8) else {
            print("[FileSystemManager] Failed to convert JSON string to data")
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
            
            // 更新缓存（NSCache是线程安全的）
            let entry = CacheEntry(items: items, timestamp: Date())
            let entryWrapper = CacheEntryWrapper(entry)
            fileCache.setObject(entryWrapper, forKey: NSString(string: cacheKey))
            
            // 记录缓存键到设备映射
            cacheKeysLock.lock()
            if deviceCacheKeys[device.id] == nil {
                deviceCacheKeys[device.id] = Set<String>()
            }
            deviceCacheKeys[device.id]?.insert(cacheKey)
            cacheKeysLock.unlock()
            
            return items
        } catch {
            print("[FileSystemManager] Failed to decode files JSON: \(error)")
            return []
        }
    }
    
    /// 获取设备根目录的文件列表
    /// - Parameter device: 目标设备
    /// - Returns: 文件列表，如果设备没有存储则返回空数组
    func getRootFiles(for device: Device) -> [FileItem] {
        guard let storage = device.storageInfo.first else {
            print("[FileSystemManager] No storage found for device \(device.id)")
            return []
        }
        
        return getFileList(for: device, parentId: FileSystemManager.RootDirectoryId, storageId: storage.storageId)
    }
    
    /// 获取指定父目录的子文件列表
    /// - Parameters:
    ///   - device: 目标设备
    ///   - parent: 父文件项
    /// - Returns: 子文件列表
    func getChildrenFiles(for device: Device, parent: FileItem) -> [FileItem] {
        return getFileList(for: device, parentId: parent.objectId, storageId: parent.storageId)
    }
    
    /// 清除所有缓存
    func clearCache() {
        fileCache.removeAllObjects()
        cacheKeysLock.lock()
        deviceCacheKeys.removeAll()
        cacheKeysLock.unlock()
        print("[FileSystemManager] Cleared all cache")
    }
    
    /// 强制清除所有缓存（与 clearCache 相同，保留以兼容性）
    func forceClearCache() {
        clearCache()
    }
    
    /// 清除指定设备的缓存
    /// - Parameter device: 目标设备
    func clearCache(for device: Device) {
        cacheKeysLock.lock()
        guard let keys = deviceCacheKeys[device.id] else {
            cacheKeysLock.unlock()
            print("[FileSystemManager] No cache found for device \(device.id)")
            return
        }
        
        // 精确清除该设备的所有缓存
        for key in keys {
            fileCache.removeObject(forKey: NSString(string: key))
        }
        
        // 从映射中移除该设备的缓存键
        deviceCacheKeys.removeValue(forKey: device.id)
        cacheKeysLock.unlock()
        
        print("[FileSystemManager] Cleared \(keys.count) cache entries for device \(device.id)")
    }
    
    // MARK: - 私有方法
    
    /// 判断缓存是否过期
    /// - Parameter timestamp: 缓存时间戳
    /// - Returns: 是否过期
    private func isExpired(_ timestamp: Date) -> Bool {
        Date().timeIntervalSince(timestamp) > FileSystemManager.CacheExpirationInterval
    }
}
