//
//  FileTransferManaging.swift
//  SwiftMTP
//
//  Protocol for file transfer operations
//

import Foundation
import Combine

/// Protocol defining file transfer management operations
/// Provides abstraction for testing and dependency injection
@MainActor
protocol FileTransferManaging: ObservableObject {
    // MARK: - Published Properties
    
    /// Active transfer tasks
    var activeTasks: [TransferTask] { get set }
    
    /// Completed transfer tasks
    var completedTasks: [TransferTask] { get set }
    
    // MARK: - Public Methods
    
    /// Download a file from device
    /// - Parameters:
    ///   - device: Source device
    ///   - fileItem: File to download
    ///   - destinationURL: Destination URL
    ///   - shouldReplace: Whether to replace existing file
    func downloadFile(from device: Device, fileItem: FileItem, to destinationURL: URL, shouldReplace: Bool)
    
    /// Upload a file to device
    /// - Parameters:
    ///   - device: Target device
    ///   - sourceURL: Source file URL
    ///   - parentId: Parent directory ID
    ///   - storageId: Storage device ID
    func uploadFile(to device: Device, sourceURL: URL, parentId: UInt32, storageId: UInt32)
    
    /// Cancel a transfer task
    /// - Parameter task: Task to cancel
    func cancelTask(_ task: TransferTask)
    
    /// Cancel all active transfer tasks
    func cancelAllTasks()
    
    /// Clear completed tasks
    func clearCompletedTasks()
}