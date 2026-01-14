//
//  AppError.swift
//  SwiftMTP
//
//  Typed error types for precise error handling
//

import Foundation

// MARK: - MTP Errors

/// MTP device-related errors
enum MTPError: Error {
    case deviceNotFound
    case deviceDisconnected
    case deviceInitializationFailed(underlying: Error)
    case deviceBusy
    case deviceTimeout
    case deviceNotSupported

    nonisolated var localizedDescription: String {
        switch self {
        case .deviceNotFound:
            return NSLocalizedString("error.mtp.deviceNotFound", value: "Device not found", comment: "MTP device not found error")
        case .deviceDisconnected:
            return NSLocalizedString("error.mtp.deviceDisconnected", value: "Device disconnected", comment: "MTP device disconnected error")
        case .deviceInitializationFailed(let error):
            let format = NSLocalizedString("error.mtp.deviceInitializationFailed", value: "Failed to initialize device: %@", comment: "MTP device initialization failed error")
            return String(format: format, String(describing: error))
        case .deviceBusy:
            return NSLocalizedString("error.mtp.deviceBusy", value: "Device is busy", comment: "MTP device busy error")
        case .deviceTimeout:
            return NSLocalizedString("error.mtp.deviceTimeout", value: "Device operation timed out", comment: "MTP device timeout error")
        case .deviceNotSupported:
            return NSLocalizedString("error.mtp.deviceNotSupported", value: "Device not supported", comment: "MTP device not supported error")
        }
    }
}

// MARK: - File System Errors

/// File system operation errors
enum FileSystemError: Error {
    case fileNotFound(objectId: UInt32)
    case folderNotFound(objectId: UInt32)
    case fileAlreadyExists(name: String)
    case invalidPath(path: String, reason: String)
    case pathTooLong(length: Int, maxLength: Int)
    case invalidFileName(name: String, reason: String)
    case permissionDenied
    case storageNotFound(storageId: UInt32)
    case storageFull(required: UInt64, available: UInt64)

    nonisolated var localizedDescription: String {
        switch self {
        case .fileNotFound(let objectId):
            let format = NSLocalizedString("error.fs.fileNotFound", value: "File not found (ID: %u)", comment: "File system file not found error")
            return String(format: format, objectId)
        case .folderNotFound(let objectId):
            let format = NSLocalizedString("error.fs.folderNotFound", value: "Folder not found (ID: %u)", comment: "File system folder not found error")
            return String(format: format, objectId)
        case .fileAlreadyExists(let name):
            let format = NSLocalizedString("error.fs.fileAlreadyExists", value: "File already exists: %@", comment: "File system file already exists error")
            return String(format: format, name)
        case .invalidPath(let path, let reason):
            let format = NSLocalizedString("error.fs.invalidPath", value: "Invalid path '%@': %@", comment: "File system invalid path error")
            return String(format: format, path, reason)
        case .pathTooLong(let length, let maxLength):
            let format = NSLocalizedString("error.fs.pathTooLong", value: "Path too long (%d characters, maximum %d)", comment: "File system path too long error")
            return String(format: format, length, maxLength)
        case .invalidFileName(let name, let reason):
            let format = NSLocalizedString("error.fs.invalidFileName", value: "Invalid file name '%@': %@", comment: "File system invalid file name error")
            return String(format: format, name, reason)
        case .permissionDenied:
            return NSLocalizedString("error.fs.permissionDenied", value: "Permission denied", comment: "File system permission denied error")
        case .storageNotFound(let storageId):
            let format = NSLocalizedString("error.fs.storageNotFound", value: "Storage not found (ID: %u)", comment: "File system storage not found error")
            return String(format: format, storageId)
        case .storageFull(let required, let available):
            let format = NSLocalizedString("error.fs.storageFull", value: "Storage full (required: %llu bytes, available: %llu bytes)", comment: "File system storage full error")
            return String(format: format, required, available)
        }
    }
}

// MARK: - Transfer Errors

/// File transfer operation errors
enum TransferError: Error {
    case transferCancelled(taskId: UUID)
    case transferFailed(fileName: String, reason: String)
    case downloadFailed(objectId: UInt32, reason: String)
    case uploadFailed(sourcePath: String, reason: String)
    case fileTooLarge(size: UInt64, maxSize: UInt64)
    case insufficientStorage(required: UInt64, available: UInt64)
    case destinationDirectoryDoesNotExist(path: String)
    case fileAlreadyExistsAtDestination(path: String)
    case corruptedFile(path: String)
    case networkError(underlying: Error)
    case timeout

    nonisolated var localizedDescription: String {
        switch self {
        case .transferCancelled(let taskId):
            let format = NSLocalizedString("error.transfer.cancelled", value: "Transfer cancelled (Task ID: %@)", comment: "Transfer cancelled error")
            return String(format: format, taskId.uuidString)
        case .transferFailed(let fileName, let reason):
            let format = NSLocalizedString("error.transfer.failed", value: "Transfer failed for '%@': %@", comment: "Transfer failed error")
            return String(format: format, fileName, reason)
        case .downloadFailed(let objectId, let reason):
            let format = NSLocalizedString("error.transfer.downloadFailed", value: "Download failed for object %u: %@", comment: "Download failed error")
            return String(format: format, objectId, reason)
        case .uploadFailed(let sourcePath, let reason):
            let format = NSLocalizedString("error.transfer.uploadFailed", value: "Upload failed for '%@': %@", comment: "Upload failed error")
            return String(format: format, sourcePath, reason)
        case .fileTooLarge(let size, let maxSize):
            let format = NSLocalizedString("error.transfer.fileTooLarge", value: "File too large (%llu bytes, maximum %llu bytes)", comment: "File too large error")
            return String(format: format, size, maxSize)
        case .insufficientStorage(let required, let available):
            let format = NSLocalizedString("error.transfer.insufficientStorage", value: "Insufficient storage space (required: %llu bytes, available: %llu bytes)", comment: "Insufficient storage error")
            return String(format: format, required, available)
        case .destinationDirectoryDoesNotExist(let path):
            let format = NSLocalizedString("error.transfer.destinationDirectoryDoesNotExist", value: "Destination directory does not exist: %@", comment: "Destination directory does not exist error")
            return String(format: format, path)
        case .fileAlreadyExistsAtDestination(let path):
            let format = NSLocalizedString("error.transfer.fileAlreadyExistsAtDestination", value: "File already exists at destination: %@", comment: "File already exists at destination error")
            return String(format: format, path)
        case .corruptedFile(let path):
            let format = NSLocalizedString("error.transfer.corruptedFile", value: "Corrupted file: %@", comment: "Corrupted file error")
            return String(format: format, path)
        case .networkError(let error):
            let format = NSLocalizedString("error.transfer.networkError", value: "Network error: %@", comment: "Network error")
            return String(format: format, String(describing: error))
        case .timeout:
            return NSLocalizedString("error.transfer.timeout", value: "Operation timed out", comment: "Operation timeout error")
        }
    }
}

// MARK: - Configuration Errors

/// Configuration-related errors
enum ConfigurationError: Error {
    case invalidConfiguration(key: String, reason: String)
    case missingConfiguration(key: String)
    case configurationLoadFailed(underlying: Error)

    nonisolated var localizedDescription: String {
        switch self {
        case .invalidConfiguration(let key, let reason):
            let format = NSLocalizedString("error.config.invalid", value: "Invalid configuration '%@': %@", comment: "Invalid configuration error")
            return String(format: format, key, reason)
        case .missingConfiguration(let key):
            let format = NSLocalizedString("error.config.missing", value: "Missing configuration: %@", comment: "Missing configuration error")
            return String(format: format, key)
        case .configurationLoadFailed(let error):
            let format = NSLocalizedString("error.config.loadFailed", value: "Failed to load configuration: %@", comment: "Configuration load failed error")
            return String(format: format, String(describing: error))
        }
    }
}

// MARK: - Scan Errors

/// Device scanning errors
enum ScanError: Error {
    case scanFailed(underlying: Error)
    case scanTimeout
    case scanCancelled
    case noDevicesFound
    case maxRetriesExceeded(retries: Int)

    nonisolated var localizedDescription: String {
        switch self {
        case .scanFailed(let error):
            let format = NSLocalizedString("error.scan.failed", value: "Scan failed: %@", comment: "Scan failed error")
            return String(format: format, String(describing: error))
        case .scanTimeout:
            return NSLocalizedString("error.scan.timeout", value: "Scan timed out", comment: "Scan timeout error")
        case .scanCancelled:
            return NSLocalizedString("error.scan.cancelled", value: "Scan cancelled", comment: "Scan cancelled error")
        case .noDevicesFound:
            return NSLocalizedString("error.scan.noDevicesFound", value: "No devices found", comment: "No devices found error")
        case .maxRetriesExceeded(let retries):
            let format = NSLocalizedString("error.scan.maxRetriesExceeded", value: "Maximum retries exceeded (%d attempts)", comment: "Maximum retries exceeded error")
            return String(format: format, retries)
        }
    }
}

// MARK: - Error Extensions

extension Error {
    /// Returns a user-friendly localized description of the error
    var localizedDescription: String {
        if let appError = self as? MTPError {
            return appError.localizedDescription
        } else if let appError = self as? FileSystemError {
            return appError.localizedDescription
        } else if let appError = self as? TransferError {
            return appError.localizedDescription
        } else if let appError = self as? ConfigurationError {
            return appError.localizedDescription
        } else if let appError = self as? ScanError {
            return appError.localizedDescription
        } else {
            return self.localizedDescription
        }
    }
    
    /// Returns whether the error is recoverable
    var isRecoverable: Bool {
        if let mtpError = self as? MTPError {
            switch mtpError {
            case .deviceBusy, .deviceTimeout:
                return true
            default:
                return false
            }
        } else if let transferError = self as? TransferError {
            switch transferError {
            case .networkError, .timeout:
                return true
            default:
                return false
            }
        } else if let scanError = self as? ScanError {
            switch scanError {
            case .scanTimeout:
                return true
            default:
                return false
            }
        }
        return false
    }
}