//
//  TransferTask.swift
//  SwiftMTP
//
//  Data model representing a file transfer task
//

import Foundation
import Combine

enum TransferType: String, Codable {
    case upload = "upload"
    case download = "download"
    
    var displayName: String {
        switch self {
        case .upload: return L10n.FileTransfer.uploadType
        case .download: return L10n.FileTransfer.downloadType
        }
    }
}

enum TransferStatus: Codable, Equatable {
    case pending
    case transferring
    case paused
    case completed
    case failed(String)
    case cancelled
    
    var displayName: String {
        switch self {
        case .pending: return L10n.FileTransfer.statusPending
        case .transferring: return L10n.FileTransfer.statusTransferring
        case .paused: return L10n.FileTransfer.statusPaused
        case .completed: return L10n.FileTransfer.statusCompleted
        case .failed(let error): return L10n.FileTransfer.statusFailed.localized(error)
        case .cancelled: return L10n.FileTransfer.statusCancelled
        }
    }
    
    var isActive: Bool {
        switch self {
        case .transferring, .pending:
            return true
        default:
            return false
        }
    }
}

class TransferTask: Identifiable, ObservableObject {
    let id: UUID
    let type: TransferType
    let fileName: String
    let sourceURL: URL
    let destinationPath: String
    let totalSize: UInt64
    
    @Published var transferredSize: UInt64 = 0
    @Published var status: TransferStatus = .pending
    @Published var speed: Double = 0
    @Published var startTime: Date?
    @Published var endTime: Date?
    
    private var _isCancelled = false
    private let cancelLock = NSLock()
    
    var isCancelled: Bool {
        get {
            cancelLock.lock()
            defer { cancelLock.unlock() }
            return _isCancelled
        }
        set {
            cancelLock.lock()
            defer { cancelLock.unlock() }
            _isCancelled = newValue
        }
    }
    
    var progress: Double {
        guard totalSize > 0 else { return 0 }
        return Double(transferredSize) / Double(totalSize)
    }
    
    var formattedProgress: String {
        String(format: "%.1f%%", progress * 100)
    }
    
    var formattedSpeed: String {
        if speed < 1024 {
            return String(format: "%.0f B/s", speed)
        } else if speed < 1024 * 1024 {
            return String(format: "%.1f KB/s", speed / 1024)
        } else {
            return String(format: "%.1f MB/s", speed / (1024 * 1024))
        }
    }
    
    var estimatedTimeRemaining: String {
        guard speed > 0, transferredSize < totalSize else { return "--" }
        let remaining = totalSize - transferredSize
        let seconds = Double(remaining) / speed
        
        if seconds < 60 {
            return L10n.FileTransfer.estimatedTimeSeconds.localized(Int(seconds))
        } else if seconds < 3600 {
            let minutes = seconds / 60
            return L10n.FileTransfer.estimatedTimeMinutes.localized(Int(minutes))
        } else {
            let hours = seconds / 3600
            return L10n.FileTransfer.estimatedTimeHours.localized(String(format: "%.1f", hours))
        }
    }
    
    init(id: UUID = UUID(), type: TransferType, fileName: String, 
         sourceURL: URL, destinationPath: String, totalSize: UInt64) {
        self.id = id
        self.type = type
        self.fileName = fileName
        self.sourceURL = sourceURL
        self.destinationPath = destinationPath
        self.totalSize = totalSize
    }
    
    func updateProgress(transferred: UInt64, speed: Double) {
        DispatchQueue.main.async {
            self.transferredSize = transferred
            self.speed = speed
        }
    }
    
    func updateStatus(_ newStatus: TransferStatus) {
        DispatchQueue.main.async {
            self.status = newStatus
            
            switch newStatus {
            case .transferring:
                if self.startTime == nil {
                    self.startTime = Date()
                }
            case .completed, .failed, .cancelled:
                self.endTime = Date()
            default:
                break
            }
        }
    }
}
