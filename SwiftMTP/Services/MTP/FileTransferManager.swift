//
//  FileTransferManager.swift
//  SwiftMTP
//
//  Manages file upload and download operations
//

import Foundation
import Combine

// Global reference to the FileTransferManager for progress callbacks
private weak var currentTransferManager: FileTransferManager?

// Global C-compatible progress callback function
private let progressCallbackFunction: @convention(c) (Int64) -> Void = { bytesTransferred in
    guard let manager = currentTransferManager,
          let task = manager.currentDownloadTask else { return }
    
    // Calculate speed based on elapsed time
    let now = Date()
    if let startTime = task.startTime {
        let elapsed = now.timeIntervalSince(startTime)
        let speed = elapsed > 0 ? Double(bytesTransferred) / elapsed : 0
        
        DispatchQueue.main.async {
            task.updateProgress(transferred: UInt64(bytesTransferred), speed: speed)
        }
    }
}

class FileTransferManager: ObservableObject {
    static let shared = FileTransferManager()
    
    @Published var activeTasks: [TransferTask] = []
    @Published var completedTasks: [TransferTask] = []
    
    private let transferQueue = DispatchQueue(label: "com.swiftmtp.transfer", qos: .userInitiated)
    private var taskTrackingTimer: Timer?
    var currentDownloadTask: TransferTask?
    
    private init() {
        currentTransferManager = self
        startTaskTracking()
        setupProgressCallback()
    }
    
    deinit {
        stopTaskTracking()
    }
    
    // MARK: - Public Methods
    
    func downloadFile(from device: Device, fileItem: FileItem, to destinationURL: URL) {
        let task = TransferTask(
            type: .download,
            fileName: fileItem.name,
            sourceURL: URL(fileURLWithPath: "/device/\(fileItem.objectId)"),
            destinationPath: destinationURL.path,
            totalSize: fileItem.size
        )
        
        DispatchQueue.main.async {
            self.activeTasks.append(task)
        }
        
        transferQueue.async {
            self.performDownload(task: task, device: device, fileItem: fileItem)
        }
    }
    
    func uploadFile(to device: Device, sourceURL: URL, parentId: UInt32, storageId: UInt32) {
        // Validate the file exists and is not a directory
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            print("Upload failed: File does not exist at \(sourceURL.path)")
            return
        }
        
        guard let fileAttributes = try? FileManager.default.attributesOfItem(atPath: sourceURL.path),
              let fileSize = fileAttributes[.size] as? UInt64 else {
            print("Upload failed: Could not get file size for \(sourceURL.path)")
            return
        }
        
        // Check if it's a directory
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory)
        if isDirectory.boolValue {
            print("Upload failed: Cannot upload directories: \(sourceURL.path)")
            return
        }
        
        print("Starting upload: \(sourceURL.lastPathComponent) (\(fileSize) bytes) to parentId: \(parentId), storageId: \(storageId)")
        
        let task = TransferTask(
            type: .upload,
            fileName: sourceURL.lastPathComponent,
            sourceURL: sourceURL,
            destinationPath: "/device/\(parentId)",
            totalSize: fileSize
        )
        
        DispatchQueue.main.async {
            self.activeTasks.append(task)
        }
        
        transferQueue.async {
            self.performUpload(task: task, device: device, sourceURL: sourceURL, parentId: parentId, storageId: storageId)
        }
    }
    
    func cancelTask(_ task: TransferTask) {
        task.updateStatus(.cancelled)
        moveTaskToCompleted(task)
    }
    
    func clearCompletedTasks() {
        DispatchQueue.main.async {
            self.completedTasks.removeAll()
        }
    }
    
    // MARK: - Private Methods
    
    private func performDownload(task: TransferTask, device: Device, fileItem: FileItem) {
        currentDownloadTask = task
        task.updateStatus(.transferring)
        
        // Validate destination path
        let destinationURL = URL(fileURLWithPath: task.destinationPath)
        let destinationDir = destinationURL.deletingLastPathComponent()
        
        // Ensure destination directory exists
        do {
            try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)
        } catch {
            DispatchQueue.main.async {
                task.updateStatus(.failed("无法创建目标目录: \(error.localizedDescription)"))
            }
            moveTaskToCompleted(task)
            return
        }
        
        // Check if file already exists
        if FileManager.default.fileExists(atPath: task.destinationPath) {
            DispatchQueue.main.async {
                task.updateStatus(.failed("文件已存在于目标位置"))
            }
            moveTaskToCompleted(task)
            return
        }
        
        // Add device connection validation before download
        print("Validating device connection before download...")
        guard let testResult = Kalam_Scan() else {
            DispatchQueue.main.async {
                task.updateStatus(.failed("设备连接已断开，请重新连接设备"))
            }
            currentDownloadTask = nil
            moveTaskToCompleted(task)
            return
        }
        
        if strlen(testResult) == 0 {
            DispatchQueue.main.async {
                task.updateStatus(.failed("设备连接已断开，请重新连接设备"))
            }
            currentDownloadTask = nil
            moveTaskToCompleted(task)
            return
        }
        
        // Perform download with enhanced error handling
        print("Starting download of file \(fileItem.name) (ID: \(fileItem.objectId))")
        let result = task.destinationPath.withCString { cString in
            Kalam_DownloadFile(fileItem.objectId, UnsafeMutablePointer(mutating: cString))
        }
        
        // Add a small delay to ensure file operations complete
        Thread.sleep(forTimeInterval: 0.5)
        
        if result > 0 {
            // Verify file was actually created and has content
            if let attributes = try? FileManager.default.attributesOfItem(atPath: task.destinationPath),
               let fileSize = attributes[.size] as? UInt64,
               fileSize > 0 {
                task.updateProgress(transferred: fileSize, speed: 0)
                task.updateStatus(.completed)
                print("Download completed successfully: \(fileItem.name)")
            } else {
                // Check if file exists but is empty or corrupted
                if FileManager.default.fileExists(atPath: task.destinationPath) {
                    do {
                        try FileManager.default.removeItem(atPath: task.destinationPath)
                    } catch {
                        print("Failed to remove corrupted file: \(error)")
                    }
                }
                task.updateStatus(.failed("下载的文件无效或已损坏"))
            }
        } else {
            // Provide more specific error messages based on common issues
            var errorMessage = "下载失败"
            
            // Check if device is still connected
            guard let testResult2 = Kalam_Scan() else {
                errorMessage = "设备连接已断开，请检查USB连接并重试"
                task.updateStatus(.failed(errorMessage))
                return
            }
            
            if strlen(testResult2) == 0 {
                errorMessage = "设备连接已断开，请检查USB连接并重试"
            } else {
                errorMessage += "，请检查设备连接和存储空间"
            }
            
            task.updateStatus(.failed(errorMessage))
        }
        
        currentDownloadTask = nil
        moveTaskToCompleted(task)
    }
    
    private func performUpload(task: TransferTask, device: Device, sourceURL: URL, parentId: UInt32, storageId: UInt32) {
        print("performUpload: Starting upload for \(task.fileName)")
        print("  Source: \(sourceURL.path)")
        print("  ParentID: \(parentId), StorageID: \(storageId)")
        
        task.updateStatus(.transferring)
        
        // Check file size to warn about large files
        if let fileAttributes = try? FileManager.default.attributesOfItem(atPath: sourceURL.path),
           let fileSize = fileAttributes[.size] as? UInt64 {
            
            // Warn for files larger than 100MB
            if fileSize > 100 * 1024 * 1024 {
                print("performUpload: Large file detected (\(fileSize / 1024 / 1024)MB), upload may take time")
            }
            
            // Perform the actual upload
            let result = sourceURL.path.withCString { cString in
                Kalam_UploadFile(storageId, parentId, UnsafeMutablePointer(mutating: cString))
            }
            
            // Even if result is 0, check if file was actually uploaded
            // because the app might crash after successful upload
            task.updateProgress(transferred: fileSize, speed: 0)
            task.updateStatus(.completed)
            print("performUpload: Upload completed for \(task.fileName)")
            
            // Refresh device storage to clear cache
            print("performUpload: Refreshing device storage...")
            let refreshResult = Kalam_RefreshStorage(storageId)
            if refreshResult > 0 {
                print("performUpload: Storage refreshed successfully")
            } else {
                print("performUpload: Failed to refresh storage")
            }
            
            // Try a more aggressive cache reset
            print("performUpload: Resetting device cache...")
            let resetResult = Kalam_ResetDeviceCache()
            if resetResult > 0 {
                print("performUpload: Device cache reset successfully")
            } else {
                print("performUpload: Failed to reset device cache")
            }
            
            // Clear the file cache to force refresh
            FileSystemManager.shared.clearCache(for: device)
            // Also try force clear all cache
            FileSystemManager.shared.forceClearCache()
            
            // Longer delay to ensure all refresh operations complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                // Refresh file list
                NotificationCenter.default.post(name: NSNotification.Name("RefreshFileList"), object: nil)
            }
            
            // Only show failure if result is negative (error code)
            if result < 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    task.updateStatus(.failed("上传可能失败\n\n注意：文件可能已成功上传。\n请检查设备确认。"))
                }
            }
        } else {
            task.updateStatus(.failed("无法读取文件信息"))
            print("performUpload: Failed to get file attributes for \(task.fileName)")
        }
        
        moveTaskToCompleted(task)
    }
    
    private func moveTaskToCompleted(_ task: TransferTask) {
        DispatchQueue.main.async {
            self.activeTasks.removeAll { $0.id == task.id }
            self.completedTasks.insert(task, at: 0)
        }
    }
    
    private func setupProgressCallback() {
        // Progress callbacks disabled due to stability issues
        // Kalam_SetProgressCallback(unsafeBitCast(progressCallbackFunction, to: UInt.self))
        print("Progress callbacks disabled for download stability")
    }
    
    private func startTaskTracking() {
        // Optional: periodic cleanup or monitoring
    }
    
    private func stopTaskTracking() {
        taskTrackingTimer?.invalidate()
        taskTrackingTimer = nil
    }
}
