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
    private var _currentDownloadTask: TransferTask?
    private let taskLock = NSLock()
    
    // Thread-safe access to currentDownloadTask
    fileprivate var currentDownloadTask: TransferTask? {
        get {
            taskLock.lock()
            defer { taskLock.unlock() }
            return _currentDownloadTask
        }
        set {
            taskLock.lock()
            defer { taskLock.unlock() }
            _currentDownloadTask = newValue
        }
    }
    
    private init() {
        currentTransferManager = self
        startTaskTracking()
        setupProgressCallback()
    }
    
    deinit {
        stopTaskTracking()
    }
    
    // MARK: - Public Methods
    
    func downloadFile(from device: Device, fileItem: FileItem, to destinationURL: URL, shouldReplace: Bool = false) {
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
            self.performDownload(task: task, device: device, fileItem: fileItem, shouldReplace: shouldReplace)
        }
    }
    
    func uploadFile(to device: Device, sourceURL: URL, parentId: UInt32, storageId: UInt32) {
        // MARK: - 输入验证
        
        // 1. 验证文件路径不为空
        guard !sourceURL.path.isEmpty else {
            print("[FileTransferManager] Upload failed: Empty source path")
            return
        }
        
        // 2. 验证文件存在
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            print("[FileTransferManager] Upload failed: File does not exist at \(sourceURL.path)")
            return
        }
        
        // 3. 验证不是目录
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory)
        if isDirectory.boolValue {
            print("[FileTransferManager] Upload failed: Cannot upload directories: \(sourceURL.path)")
            return
        }
        
        // 4. 获取文件大小
        guard let fileAttributes = try? FileManager.default.attributesOfItem(atPath: sourceURL.path),
              let fileSize = fileAttributes[.size] as? UInt64 else {
            print("[FileTransferManager] Upload failed: Could not get file size for \(sourceURL.path)")
            return
        }
        
        // 5. 验证文件大小限制（最大 10GB）
        let maxFileSize: UInt64 = 10 * 1024 * 1024 * 1024
        guard fileSize <= maxFileSize else {
            print("[FileTransferManager] Upload failed: File too large (\(fileSize) bytes, max: \(maxFileSize) bytes)")
            return
        }
        
        // 6. 验证路径遍历攻击（更严格的检查）
        // 检查路径是否包含相对引用（..）
        let pathComponents = sourceURL.pathComponents
        guard !pathComponents.contains("..") else {
            print("[FileTransferManager] Upload failed: Invalid path with parent directory references")
            return
        }
        
        // 检查路径是否包含符号链接
        do {
            let fileAttributes = try FileManager.default.attributesOfItem(atPath: sourceURL.path)
            if let fileType = fileAttributes[.type] as? FileAttributeType,
               fileType == .typeSymbolicLink {
                print("[FileTransferManager] Upload failed: Symbolic links are not allowed")
                return
            }
        } catch {
            print("[FileTransferManager] Upload failed: Could not verify file type: \(error)")
            return
        }
        
        // 标准化路径并确保没有相对引用
        let standardizedPath = sourceURL.standardizedFileURL.path
        guard standardizedPath == sourceURL.path else {
            print("[FileTransferManager] Upload failed: Path contains relative references or symbolic links")
            return
        }
        
        // 7. 验证设备存储空间
        guard let storage = device.storageInfo.first(where: { $0.storageId == storageId }) else {
            print("[FileTransferManager] Upload failed: Storage not found (storageId: \(storageId))")
            return
        }
        
        if fileSize > storage.freeSpace {
            print("[FileTransferManager] Upload failed: Not enough space on device (required: \(fileSize), available: \(storage.freeSpace))")
            return
        }
        
        print("[FileTransferManager] Starting upload: \(sourceURL.lastPathComponent) (\(fileSize) bytes) to parentId: \(parentId), storageId: \(storageId)")
        
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
        Task { @MainActor in
            task.isCancelled = true
            task.id.uuidString.withCString { cString in
                Kalam_CancelTask(UnsafeMutablePointer(mutating: cString))
            }
            task.updateStatus(.cancelled)
            moveTaskToCompleted(task)
        }
    }
    
    /// 取消所有正在进行的传输任务
    /// 在设备断开时调用，确保任务状态一致
    func cancelAllTasks() {
        let tasksToCancel = activeTasks
        
        Task { @MainActor in
            for task in tasksToCancel {
                task.isCancelled = true
                task.id.uuidString.withCString { cString in
                    Kalam_CancelTask(UnsafeMutablePointer(mutating: cString))
                }
                task.updateStatus(.cancelled)
                moveTaskToCompleted(task)
            }
            
            print("[FileTransferManager] Cancelled \(tasksToCancel.count) active tasks")
        }
    }
    
    func clearCompletedTasks() {
    completedTasks.removeAll()
}
    
    // MARK: - Private Methods
    
    private func performDownload(task: TransferTask, device: Device, fileItem: FileItem, shouldReplace: Bool) {
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
                task.updateStatus(.failed(L10n.FileTransfer.cannotCreateDirectory.localized(error.localizedDescription)))
            }
            moveTaskToCompleted(task)
            return
        }
        
        // Check if file already exists
        if FileManager.default.fileExists(atPath: task.destinationPath) {
            if shouldReplace {
                // Remove existing file before download
                do {
                    try FileManager.default.removeItem(atPath: task.destinationPath)
                } catch {
                    DispatchQueue.main.async {
                        task.updateStatus(.failed(L10n.FileTransfer.cannotReplaceExistingFile.localized(error.localizedDescription)))
                    }
                    moveTaskToCompleted(task)
                    return
                }
            } else {
                DispatchQueue.main.async {
                    task.updateStatus(.failed(L10n.FileTransfer.fileAlreadyExistsAtDestination))
                }
                moveTaskToCompleted(task)
                return
            }
        }
        
        // Add device connection validation before download
        print("Validating device connection before download...")
        guard let testResult = Kalam_Scan() else {
            DispatchQueue.main.async {
                task.updateStatus(.failed(L10n.FileTransfer.deviceDisconnectedReconnect))
            }
            currentDownloadTask = nil
            moveTaskToCompleted(task)
            return
        }
        
        if strlen(testResult) == 0 {
            DispatchQueue.main.async {
                task.updateStatus(.failed(L10n.FileTransfer.deviceDisconnectedReconnect))
            }
            currentDownloadTask = nil
            moveTaskToCompleted(task)
            return
        }
        
        // Perform download with enhanced error handling
        print("Starting download of file \(fileItem.name) (ID: \(fileItem.objectId))")
        let result = task.destinationPath.withCString { cString in
            task.id.uuidString.withCString { taskCString in
                Kalam_DownloadFile(fileItem.objectId, UnsafeMutablePointer(mutating: cString), UnsafeMutablePointer(mutating: taskCString))
            }
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
                task.updateStatus(.failed(L10n.FileTransfer.downloadedFileInvalidOrCorrupted))
            }
        } else {
            // Provide more specific error messages based on common issues
            var errorMessage = L10n.FileTransfer.downloadFailed
            
            // Check if device is still connected
            guard let testResult2 = Kalam_Scan() else {
                errorMessage = L10n.FileTransfer.deviceDisconnectedCheckUSB
                task.updateStatus(.failed(errorMessage))
                return
            }
            
            if strlen(testResult2) == 0 {
                errorMessage = L10n.FileTransfer.deviceDisconnectedCheckUSB
            } else {
                errorMessage = L10n.FileTransfer.checkConnectionAndStorage
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

        guard let fileAttributes = try? FileManager.default.attributesOfItem(atPath: sourceURL.path),
              let fileSize = fileAttributes[.size] as? UInt64 else {
            task.updateStatus(.failed(L10n.FileTransfer.cannotReadFileInfo))
            print("performUpload: Failed to get file attributes for \(task.fileName)")
            moveTaskToCompleted(task)
            return
        }

        if fileSize > 100 * 1024 * 1024 {
            print("performUpload: Large file detected (\(fileSize / 1024 / 1024)MB), upload may take time")
        }

        if task.isCancelled {
            task.updateStatus(.cancelled)
            moveTaskToCompleted(task)
            return
        }

        let uploadResult = sourceURL.path.withCString { sourceCString in
            task.id.uuidString.withCString { taskCString in
                Kalam_UploadFile(storageId, parentId, UnsafeMutablePointer(mutating: sourceCString), UnsafeMutablePointer(mutating: taskCString))
            }
        }

        if task.isCancelled {
            task.updateStatus(.cancelled)
            moveTaskToCompleted(task)
            return
        }

        if uploadResult > 0 {
            task.updateProgress(transferred: fileSize, speed: 0)
            task.updateStatus(.completed)
            print("performUpload: Upload completed successfully for \(task.fileName)")
        } else {
            task.updateStatus(.failed(L10n.FileTransfer.uploadFailed))
            print("performUpload: Upload failed for \(task.fileName)")
        }

        print("performUpload: Refreshing device storage...")
        let refreshResult = Kalam_RefreshStorage(storageId)
        if refreshResult > 0 {
            print("performUpload: Storage refreshed successfully")
        } else {
            print("performUpload: Failed to refresh storage")
        }

        print("performUpload: Resetting device cache...")
        let resetResult = Kalam_ResetDeviceCache()
        if resetResult > 0 {
            print("performUpload: Device cache reset successfully")
        } else {
            print("performUpload: Failed to reset device cache")
        }

        FileSystemManager.shared.clearCache(for: device)
        FileSystemManager.shared.forceClearCache()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            NotificationCenter.default.post(name: NSNotification.Name("RefreshFileList"), object: nil)
        }

        moveTaskToCompleted(task)
    }
    
    private func moveTaskToCompleted(_ task: TransferTask) {
        DispatchQueue.main.async {
            if self.completedTasks.contains(where: { $0.id == task.id }) {
                return
            }
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
