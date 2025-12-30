//
//  TransferTask.swift
//  SwiftMTP
//
//  Data model representing a file transfer task
//

import Foundation
import Combine

// MARK: - TransferType

/// 文件传输类型枚举
enum TransferType: String, Codable {
    case upload = "upload"
    case download = "download"
    
    /// 传输类型的本地化显示名称
    var displayName: String {
        switch self {
        case .upload: return L10n.FileTransfer.uploadType
        case .download: return L10n.FileTransfer.downloadType
        }
    }
}

// MARK: - TransferStatus

/// 文件传输状态枚举
enum TransferStatus: Codable, Equatable {
    case pending           // 等待中
    case transferring      // 传输中
    case paused           // 已暂停
    case completed        // 已完成
    case failed(String)   // 失败（包含错误信息）
    case cancelled        // 已取消
    
    /// 状态的本地化显示名称
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
    
    /// 判断状态是否为活跃状态（正在传输或等待中）
    var isActive: Bool {
        switch self {
        case .transferring, .pending:
            return true
        default:
            return false
        }
    }
}

// MARK: - TransferTask

/// 文件传输任务模型
/// 使用 @MainActor 确保所有属性更新都在主线程上执行，避免线程安全问题
@MainActor
class TransferTask: Identifiable, ObservableObject {
    // MARK: - 常量
    
    /// 最大文件大小限制（10GB）
    private static let MaxFileSize: UInt64 = 10 * 1024 * 1024 * 1024
    
    // MARK: - 属性
    
    /// 任务唯一标识符
    let id: UUID
    
    /// 传输类型（上传/下载）
    let type: TransferType
    
    /// 文件名称
    let fileName: String
    
    /// 源文件 URL
    let sourceURL: URL
    
    /// 目标路径
    let destinationPath: String
    
    /// 文件总大小（字节）
    let totalSize: UInt64
    
    /// 已传输大小（字节）
    @Published var transferredSize: UInt64 = 0
    
    /// 传输状态
    @Published var status: TransferStatus = .pending
    
    /// 传输速度（字节/秒）
    @Published var speed: Double = 0
    
    /// 传输开始时间
    @Published var startTime: Date?
    
    /// 传输结束时间
    @Published var endTime: Date?
    
    // MARK: - 私有属性
    
    /// 任务是否已取消（内部状态）
    /// Note: @MainActor ensures thread safety, no lock needed
    var isCancelled = false
    
    // MARK: - 计算属性
    
    /// 传输进度（0.0 - 1.0）
    var progress: Double {
        guard totalSize > 0 else { return 0 }
        return Double(transferredSize) / Double(totalSize)
    }
    
    /// 格式化的进度百分比字符串
    var formattedProgress: String {
        String(format: "%.1f%%", progress * 100)
    }
    
    /// 格式化的传输速度字符串
    var formattedSpeed: String {
        if speed < 1024 {
            return String(format: "%.0f B/s", speed)
        } else if speed < 1024 * 1024 {
            return String(format: "%.1f KB/s", speed / 1024)
        } else {
            return String(format: "%.1f MB/s", speed / (1024 * 1024))
        }
    }
    
    /// 预计剩余时间字符串
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
    
    // MARK: - 初始化
    
    /// 初始化传输任务
    /// - Parameters:
    ///   - id: 任务唯一标识符（默认自动生成）
    ///   - type: 传输类型
    ///   - fileName: 文件名称
    ///   - sourceURL: 源文件 URL
    ///   - destinationPath: 目标路径
    ///   - totalSize: 文件总大小
    init(id: UUID = UUID(), type: TransferType, fileName: String, 
         sourceURL: URL, destinationPath: String, totalSize: UInt64) {
        self.id = id
        self.type = type
        self.fileName = fileName
        self.sourceURL = sourceURL
        self.destinationPath = destinationPath
        self.totalSize = totalSize
    }
    
    // MARK: - 公共方法
    
    /// 更新传输进度
    /// - Parameters:
    ///   - transferred: 已传输的字节数
    ///   - speed: 当前传输速度（字节/秒）
    func updateProgress(transferred: UInt64, speed: Double) {
        // 使用 @MainActor 确保在主线程上更新
        self.transferredSize = transferred
        self.speed = speed
    }
    
    /// 更新传输状态
    /// - Parameter newStatus: 新的传输状态
    func updateStatus(_ newStatus: TransferStatus) {
        // 使用 @MainActor 确保在主线程上更新
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
