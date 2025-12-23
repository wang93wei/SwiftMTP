//
//  TransferTask.swift
//  SwiftMTP
//
//  Data model representing a file transfer task
//

import Foundation
import Combine

enum TransferType: String, Codable {
    case upload = "上传"
    case download = "下载"
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
        case .pending: return "等待中"
        case .transferring: return "传输中"
        case .paused: return "已暂停"
        case .completed: return "已完成"
        case .failed(let error): return "失败: \(error)"
        case .cancelled: return "已取消"
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
            return String(format: "%.0f 秒", seconds)
        } else if seconds < 3600 {
            return String(format: "%.0f 分钟", seconds / 60)
        } else {
            return String(format: "%.1f 小时", seconds / 3600)
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
