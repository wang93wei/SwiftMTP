//
//  FileSystemManaging.swift
//  SwiftMTP
//
//  Protocol for file system operations
//

import Foundation

/// Protocol defining file system management operations
/// Provides abstraction for testing and dependency injection
protocol FileSystemManaging {
    // MARK: - Public Methods
    
    /// Get file list for a specified directory
    /// - Parameters:
    ///   - device: Target device
    ///   - parentId: Parent directory ID (defaults to root directory)
    ///   - storageId: Storage device ID
    /// - Returns: File list, empty array if retrieval fails
    func getFileList(for device: Device, parentId: UInt32, storageId: UInt32) -> [FileItem]
    
    /// Get file list for device root directory
    /// - Parameter device: Target device
    /// - Returns: File list, empty array if device has no storage
    func getRootFiles(for device: Device) -> [FileItem]
    
    /// Get child files for a specified parent directory
    /// - Parameters:
    ///   - device: Target device
    ///   - parent: Parent file item
    /// - Returns: Child file list
    func getChildrenFiles(for device: Device, parent: FileItem) -> [FileItem]
    
    /// Clear all cache
    func clearCache()
    
    /// Force clear all cache (for compatibility)
    func forceClearCache()
    
    /// Clear cache for a specific device
    /// - Parameter device: Target device
    func clearCache(for device: Device)
}