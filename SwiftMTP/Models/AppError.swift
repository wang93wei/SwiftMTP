//
//  AppError.swift
//  SwiftMTP
//
//  Unified error types for the application
//  Provides typed errors and localized error messages
//

import Foundation

/// Unified application error types
/// Supports Swift 6 typed throws and provides localized error messages
enum AppError: LocalizedError, CustomStringConvertible, Equatable {
    
    // MARK: - Device Errors
    
    /// Device disconnected
    case deviceDisconnected
    
    /// Device not found
    case deviceNotFound
    
    /// Device scan failed
    case deviceScanFailed
    
    // MARK: - File System Errors
    
    /// File not found
    case fileNotFound(String)
    
    /// Invalid file path
    case invalidPath(String)
    
    /// File already exists
    case fileAlreadyExists(String)
    
    /// Directory creation failed
    case directoryCreationFailed(String)
    
    /// File deletion failed
    case fileDeletionFailed(String)
    
    // MARK: - Transfer Errors
    
    /// Upload failed
    case uploadFailed(String)
    
    /// Download failed
    case downloadFailed(String)
    
    /// Transfer cancelled
    case transferCancelled
    
    /// Insufficient storage space
    case insufficientStorage
    
    /// File too large
    case fileTooLarge(UInt64)
    
    /// Cannot create directory
    case cannotCreateDirectory
    
    /// Cannot read file info
    case cannotReadFileInfo
    
    /// Cannot replace existing file
    case cannotReplaceExistingFile
    
    /// File already exists at destination
    case fileAlreadyExistsAtDestination
    
    /// Downloaded file invalid or corrupted
    case downloadedFileInvalidOrCorrupted
    
    /// Device disconnected, reconnect
    case deviceDisconnectedReconnect
    
    /// Device disconnected, check USB
    case deviceDisconnectedCheckUSB
    
    /// Check connection and storage
    case checkConnectionAndStorage
    
    // MARK: - Validation Errors
    
    /// Invalid input
    case invalidInput(String)
    
    /// Invalid file type
    case invalidFileType
    
    /// Path contains invalid characters
    case pathContainsInvalidCharacters
    
    /// Path too long
    case pathTooLong
    
    /// Symbolic link not allowed
    case symbolicLinkNotAllowed
    
    /// Path not in allowed directories
    case pathNotInAllowedDirectories
    
    // MARK: - Cache Errors
    
    /// Cache invalidation failed
    case cacheInvalidationFailed
    
    // MARK: - Localization Errors
    
    /// Language bundle load failed
    case languageBundleLoadFailed(String)
    
    // MARK: - General Errors
    
    /// Operation failed
    case operationFailed(String)
    
    /// Unknown error
    case unknown
    
    // MARK: - LocalizedError
    
    var errorDescription: String? {
        switch self {
        // Device errors
        case .deviceDisconnected:
            return "Device Disconnected"
        case .deviceNotFound:
            return "Device not found"
        case .deviceScanFailed:
            return "Failed to scan for devices"
            
        // File system errors
        case .fileNotFound(let fileName):
            return "File not found: \(fileName)"
        case .invalidPath(let path):
            return "Invalid path: \(path)"
        case .fileAlreadyExists(let fileName):
            return "File already exists: \(fileName)"
        case .directoryCreationFailed(let path):
            return "Failed to create directory: \(path)"
        case .fileDeletionFailed(let fileName):
            return "Failed to delete file: \(fileName)"
            
        // Transfer errors
        case .uploadFailed(let message):
            return "Upload failed: \(message)"
        case .downloadFailed(let message):
            return "Download failed: \(message)"
        case .transferCancelled:
            return "Transfer cancelled"
        case .insufficientStorage:
            return "Insufficient storage space"
        case .fileTooLarge(let size):
            return "File too large: \(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))"
        case .cannotCreateDirectory:
            return "Cannot create destination directory"
        case .cannotReadFileInfo:
            return "Cannot read file information"
        case .cannotReplaceExistingFile:
            return "Cannot replace existing file"
        case .fileAlreadyExistsAtDestination:
            return "File already exists at destination"
        case .downloadedFileInvalidOrCorrupted:
            return "Downloaded file is invalid or corrupted"
        case .deviceDisconnectedReconnect:
            return "Device disconnected, please reconnect the device"
        case .deviceDisconnectedCheckUSB:
            return "Device disconnected, please check USB connection and try again"
        case .checkConnectionAndStorage:
            return "Download failed, please check device connection and storage space"
            
        // Validation errors
        case .invalidInput(let message):
            return "Invalid input: \(message)"
        case .invalidFileType:
            return "Invalid file type"
        case .pathContainsInvalidCharacters:
            return "Path contains invalid characters"
        case .pathTooLong:
            return "Path too long"
        case .symbolicLinkNotAllowed:
            return "Symbolic links are not allowed"
        case .pathNotInAllowedDirectories:
            return "Path is not in allowed directories"
            
        // Cache errors
        case .cacheInvalidationFailed:
            return "Cache invalidation failed"
            
        // Localization errors
        case .languageBundleLoadFailed(let locale):
            return "Failed to load language bundle for: \(locale)"
            
        // General errors
        case .operationFailed(let message):
            return "Operation failed: \(message)"
        case .unknown:
            return "Unknown error"
        }
    }
    
    var failureReason: String? {
        switch self {
        case .deviceDisconnected:
            return "The device has been disconnected"
        case .deviceNotFound:
            return "The requested device could not be found"
        case .deviceScanFailed:
            return "Failed to scan for devices"
        case .fileNotFound:
            return "The specified file could not be found"
        case .invalidPath:
            return "The file path is invalid"
        case .uploadFailed:
            return "File upload operation failed"
        case .downloadFailed:
            return "File download operation failed"
        case .insufficientStorage:
            return "Not enough storage space available"
        case .fileTooLarge:
            return "File size exceeds maximum allowed limit"
        case .pathContainsInvalidCharacters:
            return "File path contains invalid characters"
        case .symbolicLinkNotAllowed:
            return "Symbolic links are not allowed"
        case .pathNotInAllowedDirectories:
            return "File path is not in allowed directories"
        default:
            return nil
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .deviceDisconnected:
            return "Please reconnect the device and try again"
        case .insufficientStorage:
            return "Please free up some space and try again"
        case .fileTooLarge:
            return "Please select a smaller file"
        case .pathNotInAllowedDirectories:
            return "Please select a file from Downloads, Desktop, or Documents"
        default:
            return nil
        }
    }
    
    // MARK: - CustomStringConvertible
    
    var description: String {
        return errorDescription ?? "Unknown error"
    }
    
    // MARK: - Equatable
    
    static func == (lhs: AppError, rhs: AppError) -> Bool {
        switch (lhs, rhs) {
        case (.deviceDisconnected, .deviceDisconnected),
             (.deviceNotFound, .deviceNotFound),
             (.deviceScanFailed, .deviceScanFailed),
             (.transferCancelled, .transferCancelled),
             (.insufficientStorage, .insufficientStorage),
             (.cannotCreateDirectory, .cannotCreateDirectory),
             (.cannotReadFileInfo, .cannotReadFileInfo),
             (.cannotReplaceExistingFile, .cannotReplaceExistingFile),
             (.fileAlreadyExistsAtDestination, .fileAlreadyExistsAtDestination),
             (.downloadedFileInvalidOrCorrupted, .downloadedFileInvalidOrCorrupted),
             (.deviceDisconnectedReconnect, .deviceDisconnectedReconnect),
             (.deviceDisconnectedCheckUSB, .deviceDisconnectedCheckUSB),
             (.checkConnectionAndStorage, .checkConnectionAndStorage),
             (.invalidFileType, .invalidFileType),
             (.pathContainsInvalidCharacters, .pathContainsInvalidCharacters),
             (.pathTooLong, .pathTooLong),
             (.symbolicLinkNotAllowed, .symbolicLinkNotAllowed),
             (.pathNotInAllowedDirectories, .pathNotInAllowedDirectories),
             (.cacheInvalidationFailed, .cacheInvalidationFailed),
             (.unknown, .unknown):
            return true
        case (.fileNotFound(let lhsFile), .fileNotFound(let rhsFile)):
            return lhsFile == rhsFile
        case (.invalidPath(let lhsPath), .invalidPath(let rhsPath)):
            return lhsPath == rhsPath
        case (.fileAlreadyExists(let lhsFile), .fileAlreadyExists(let rhsFile)):
            return lhsFile == rhsFile
        case (.directoryCreationFailed(let lhsPath), .directoryCreationFailed(let rhsPath)):
            return lhsPath == rhsPath
        case (.fileDeletionFailed(let lhsFile), .fileDeletionFailed(let rhsFile)):
            return lhsFile == rhsFile
        case (.uploadFailed(let lhsMessage), .uploadFailed(let rhsMessage)):
            return lhsMessage == rhsMessage
        case (.downloadFailed(let lhsMessage), .downloadFailed(let rhsMessage)):
            return lhsMessage == rhsMessage
        case (.fileTooLarge(let lhsSize), .fileTooLarge(let rhsSize)):
            return lhsSize == rhsSize
        case (.invalidInput(let lhsMessage), .invalidInput(let rhsMessage)):
            return lhsMessage == rhsMessage
        case (.operationFailed(let lhsMessage), .operationFailed(let rhsMessage)):
            return lhsMessage == rhsMessage
        case (.languageBundleLoadFailed(let lhsLocale), .languageBundleLoadFailed(let rhsLocale)):
            return lhsLocale == rhsLocale
        default:
            return false
        }
    }
}

// MARK: - Error Categories

extension AppError {
    /// Whether the error is recoverable
    var isRecoverable: Bool {
        switch self {
        case .deviceDisconnected,
             .deviceScanFailed,
             .transferCancelled,
             .insufficientStorage,
             .fileTooLarge,
             .pathNotInAllowedDirectories:
            return true
        default:
            return false
        }
    }
    
    /// Whether the error is critical (requires user intervention)
    var isCritical: Bool {
        switch self {
        case .deviceDisconnected,
             .insufficientStorage,
             .pathNotInAllowedDirectories,
             .symbolicLinkNotAllowed:
            return true
        default:
            return false
        }
    }
    
    /// Error category for logging and analytics
    var category: String {
        switch self {
        case .deviceDisconnected, .deviceNotFound, .deviceScanFailed:
            return "device"
        case .fileNotFound, .invalidPath, .fileAlreadyExists, .directoryCreationFailed, .fileDeletionFailed:
            return "filesystem"
        case .uploadFailed, .downloadFailed, .transferCancelled, .insufficientStorage, .fileTooLarge:
            return "transfer"
        case .invalidInput, .invalidFileType, .pathContainsInvalidCharacters, .pathTooLong, .symbolicLinkNotAllowed, .pathNotInAllowedDirectories:
            return "validation"
        case .cacheInvalidationFailed:
            return "cache"
        case .languageBundleLoadFailed:
            return "localization"
        case .operationFailed, .unknown:
            return "general"
        default:
            return "other"
        }
    }
}