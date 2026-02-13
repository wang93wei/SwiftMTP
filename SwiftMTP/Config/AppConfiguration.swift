//
//  AppConfiguration.swift
//  SwiftMTP
//
//  Centralized application configuration
//  Eliminates duplicate constant definitions and provides single source of truth
//

import Foundation

/// Centralized application configuration
/// Provides single source of truth for all app constants and settings
struct AppConfiguration {
    
    // MARK: - MTP Protocol Constants
    
    /// Root directory ID (MTP protocol standard value)
    static let rootDirectoryId: UInt32 = 0xFFFFFFFF
    
    // MARK: - File Transfer Constants
    
    /// Maximum file size limit (10GB)
    static let maxFileSize: UInt64 = 10 * 1024 * 1024 * 1024
    
    // MARK: - Device Scanning Constants
    
    /// Default scan interval in seconds
    static let defaultScanInterval: TimeInterval = 3.0
    
    /// Scan interval when device is connected (seconds)
    static let connectedDeviceScanInterval: TimeInterval = 5.0
    
    /// Maximum scan interval for exponential backoff (seconds)
    static let maxScanInterval: TimeInterval = 30.0
    
    /// Maximum consecutive failures before stopping automatic scan
    static let maxFailuresBeforeManualRefresh: Int = 3
    
    // MARK: - Cache Configuration
    
    /// Cache expiration time in seconds
    static let cacheExpirationInterval: TimeInterval = 60.0
    
    /// Maximum number of directories to cache
    static let fileCacheCountLimit: Int = 1000
    
    /// Total cache size limit in bytes (50MB)
    static let fileCacheTotalCostLimit: Int = 50 * 1024 * 1024
    
    /// Maximum number of devices to cache
    static let deviceCacheCountLimit: Int = 100
    
    /// Device cache total cost limit in bytes (10MB)
    static let deviceCacheTotalCostLimit: Int = 10 * 1024 * 1024
    
    /// Device serial cache total cost limit in bytes (10KB)
    static let deviceSerialCacheTotalCostLimit: Int = 10 * 1024
    
    // MARK: - Logging Configuration
    
    /// Enable debug logging
    #if DEBUG
    static let enableDebugLogging: Bool = true
    #else
    static let enableDebugLogging: Bool = false
    #endif
    
    // MARK: - User Defaults Keys
    
    /// UserDefaults key for app language
    static let languageKey = "appLanguage"
    
    /// UserDefaults key for scan interval
    static let scanIntervalKey = "scanInterval"
    
    /// UserDefaults key for automatic update checking
    static let autoCheckUpdatesKey = "autoCheckUpdates"
    
    /// UserDefaults key for last update check timestamp
    static let lastUpdateCheckKey = "lastUpdateCheckDate"
    
    // MARK: - Update Checking Configuration
    
    /// GitHub repository owner
    static let githubRepoOwner = "wang93wei"
    
    /// GitHub repository name
    static let githubRepoName = "SwiftMTP"
    
    /// GitHub Wiki URL
    static let githubWikiURL = "https://github.com/wang93wei/SwiftMTP/wiki"
    
    /// Update check timeout in seconds
    static let updateCheckTimeout: TimeInterval = 30.0
    
    /// Automatic update check interval in seconds (24 hours)
    static let autoCheckInterval: TimeInterval = 24 * 60 * 60
    
    // MARK: - Security Configuration
    
    /// Maximum path length to prevent buffer overflow
    static let maxPathLength: Int = 4096
    
    /// Allowed directories for file upload
    /// No directory restrictions - users can upload from any location
    /// Security is maintained through path traversal checks and symbolic link blocking
    static var allowedUploadDirectories: [URL] {
        // No restrictions - allow all paths
        // Security is enforced by validatePathSecurity() in FileTransferManager
        return []
    }
    
    // MARK: - UI Configuration
    
    /// Default window width
    static let defaultWindowWidth: CGFloat = 1200
    
    /// Default window height
    static let defaultWindowHeight: CGFloat = 800
    
    /// Navigation split view column dimensions
    static let navigationColumnMinWidth: CGFloat = 200
    static let navigationColumnIdealWidth: CGFloat = 250
    static let navigationColumnMaxWidth: CGFloat = 300
    
    // MARK: - Validation
    
    /// Validate file size against maximum limit
    /// - Parameter fileSize: File size in bytes
    /// - Returns: True if file size is valid
    static func isValidFileSize(_ fileSize: UInt64) -> Bool {
        return fileSize <= maxFileSize
    }
    
    /// Validate scan interval
    /// - Parameter interval: Scan interval in seconds
    /// - Returns: True if interval is valid
    static func isValidScanInterval(_ interval: TimeInterval) -> Bool {
        return interval >= 1.0 && interval <= maxScanInterval
    }
    
    /// Validate path length
    /// - Parameter path: File path
    /// - Returns: True if path length is valid
    static func isValidPathLength(_ path: String) -> Bool {
        return path.count <= maxPathLength
    }
}