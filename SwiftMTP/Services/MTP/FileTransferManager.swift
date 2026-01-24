//
//  FileTransferManager.swift
//  SwiftMTP
//
//  Manages file upload and download operations
//

import Foundation
import Combine
import Darwin

// Debug logging helper - only outputs in Debug mode
private func debugLog(_ message: String) {
    #if DEBUG
    print(message)
    #endif
}

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
        // Timer cleanup will be handled by automatic deallocation
        // No manual cleanup needed as Timer will be released with the instance
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
            debugLog("[FileTransferManager] Upload failed: Empty source path")
            return
        }
        
        // 2. 验证文件存在
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            debugLog("[FileTransferManager] Upload failed: File does not exist at \(sourceURL.path)")
            return
        }
        
        // 3. 验证不是目录
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory)
        if isDirectory.boolValue {
            debugLog("[FileTransferManager] Upload failed: Cannot upload directories: \(sourceURL.path)")
            return
        }
        
        // 4. 获取文件大小
        guard let fileAttributes = try? FileManager.default.attributesOfItem(atPath: sourceURL.path),
              let fileSize = fileAttributes[.size] as? UInt64 else {
            debugLog("[FileTransferManager] Upload failed: Could not get file size for \(sourceURL.path)")
            return
        }
        
        // 5. 验证文件大小限制（最大 10GB）
        let maxFileSize: UInt64 = 10 * 1024 * 1024 * 1024
        guard fileSize <= maxFileSize else {
            debugLog("[FileTransferManager] Upload failed: File too large (\(fileSize) bytes, max: \(maxFileSize) bytes)")
            return
        }
        
        // 6. 验证路径遍历攻击（更严格的检查）
        guard validatePathSecurity(sourceURL) else {
            return
        }
        
        // 7. 验证设备存储空间
        guard let storage = device.storageInfo.first(where: { $0.storageId == storageId }) else {
            debugLog("[FileTransferManager] Upload failed: Storage not found (storageId: \(storageId))")
            return
        }
        
        if fileSize > storage.freeSpace {
            debugLog("[FileTransferManager] Upload failed: Not enough space on device (required: \(fileSize), available: \(storage.freeSpace))")
            return
        }
        
        debugLog("[FileTransferManager] Starting upload: \(sourceURL.lastPathComponent) (\(fileSize) bytes) to parentId: \(parentId), storageId: \(storageId)")
        
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

            debugLog("[FileTransferManager] Cancelled \(tasksToCancel.count) active tasks")
        }
    }

    func clearCompletedTasks() {
    completedTasks.removeAll()
}

    // MARK: - Parallel Operations with TaskGroup

    /// Download multiple files in parallel using TaskGroup
    /// - Parameters:
    ///   - device: Target device
    ///   - fileItems: Array of file items to download
    ///   - destinationURL: Base destination URL
    ///   - maxConcurrent: Maximum number of concurrent downloads (default: 3)
    /// - Returns: Array of transfer tasks
    /// - Note: This method is disabled due to Swift 6 concurrency restrictions on FileTransferManager
    @MainActor
    func downloadMultipleFiles(
        from device: Device,
        fileItems: [FileItem],
        to destinationURL: URL,
        maxConcurrent: Int = 3
    ) -> [TransferTask] {
        // Due to Swift 6 concurrency restrictions, this method is disabled
        // Use individual downloadFile calls instead
        debugLog("[FileTransferManager] downloadMultipleFiles is disabled due to Swift 6 concurrency restrictions")
        return []
    }

    /// Upload multiple files in parallel using TaskGroup
    /// - Parameters:
    ///   - device: Target device
    ///   - sourceURLs: Array of source file URLs
    ///   - parentId: Parent directory ID
    ///   - storageId: Storage ID
    ///   - maxConcurrent: Maximum number of concurrent uploads (default: 2)
    /// - Returns: Array of transfer tasks
    /// - Note: This method is disabled due to Swift 6 concurrency restrictions on FileTransferManager
    @MainActor
    func uploadMultipleFiles(
        to device: Device,
        sourceURLs: [URL],
        parentId: UInt32,
        storageId: UInt32,
        maxConcurrent: Int = 2
    ) -> [TransferTask] {
        // Due to Swift 6 concurrency restrictions, this method is disabled
        // Use individual uploadFile calls instead
        debugLog("[FileTransferManager] uploadMultipleFiles is disabled due to Swift 6 concurrency restrictions")
        return []
    }
    
    // MARK: - Private Methods
    
    private func validatePathSecurity(_ url: URL) -> Bool {
        debugLog("validatePathSecurity: Starting path security validation")
        debugLog("validatePathSecurity: Original path: \(url.path)")

        // 1. 验证路径长度限制（防止缓冲区溢出）
        let maxPathLength = 4096
        let pathLength = url.path.count
        debugLog("validatePathSecurity: Step 1 - Checking path length: \(pathLength) characters (max: \(maxPathLength))")
        guard pathLength <= maxPathLength else {
            debugLog("[FileTransferManager] Upload failed: Path too long (\(pathLength) characters, max: \(maxPathLength))")
            return false
        }
        debugLog("validatePathSecurity: Step 1 - Path length OK")

        // 2. 解析并标准化路径
        let standardizedPath = url.standardizedFileURL.path
        debugLog("validatePathSecurity: Step 2 - Standardized path: \(standardizedPath)")

        // 3. 检查路径是否包含相对引用（包括 URL 编码）
        // 只检查父目录引用（..），不检查当前目录引用（.），以允许隐藏文件
        let pathComponents = standardizedPath.split(separator: "/")
        let dangerousPatterns = ["..", "%2e%2e", "%2E%2E"]
        debugLog("validatePathSecurity: Step 3 - Checking for dangerous patterns...")
        debugLog("validatePathSecurity:   Path components: \(pathComponents.count)")
        for component in pathComponents {
            for pattern in dangerousPatterns {
                if component.lowercased().contains(pattern.lowercased()) {
                    debugLog("[FileTransferManager] Upload failed: Invalid path with parent directory references or encoded dots")
                    debugLog("validatePathSecurity:   Found dangerous pattern '\(pattern)' in component '\(component)'")
                    return false
                }
            }
        }
        debugLog("validatePathSecurity: Step 3 - No dangerous patterns found")

        // 4. 检查特殊字符（防止命令注入）
        let dangerousChars = CharacterSet(charactersIn: "\u{0000}\n\r\t")
        debugLog("validatePathSecurity: Step 4 - Checking for control characters...")
        if standardizedPath.rangeOfCharacter(from: dangerousChars) != nil {
            debugLog("[FileTransferManager] Upload failed: Path contains invalid control characters")
            return false
        }
        debugLog("validatePathSecurity: Step 4 - No control characters found")

        // 5. 检查符号链接
        debugLog("validatePathSecurity: Step 5 - Checking for symbolic links...")
        do {
            let fileAttributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let fileType = fileAttributes[.type] as? FileAttributeType,
               fileType == .typeSymbolicLink {
                debugLog("[FileTransferManager] Upload failed: Symbolic links are not allowed")
                return false
            }
            debugLog("validatePathSecurity: Step 5 - Not a symbolic link, file type: \(fileAttributes[.type] ?? "unknown")")
        } catch {
            debugLog("[FileTransferManager] Upload failed: Could not verify file type: \(error)")
            return false
        }

        // 6. 验证路径是否在允许的目录范围内
        let allowedDirectories = [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads").path,
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop").path,
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents").path
        ]
        debugLog("validatePathSecurity: Step 6 - Checking allowed directories...")
        debugLog("validatePathSecurity:   Allowed directories:")
        for dir in allowedDirectories {
            debugLog("validatePathSecurity:     - \(dir)")
        }

        var isInAllowedDirectory = false
        for allowedDir in allowedDirectories {
            if standardizedPath.hasPrefix(allowedDir) {
                isInAllowedDirectory = true
                debugLog("validatePathSecurity:   Path matches allowed directory: \(allowedDir)")
                break
            }
        }

        if !isInAllowedDirectory {
            debugLog("[FileTransferManager] Upload failed: Path is not in allowed directories")
            debugLog("[FileTransferManager] Allowed directories: \(allowedDirectories)")
            debugLog("[FileTransferManager] Actual path: \(standardizedPath)")
            return false
        }
        debugLog("validatePathSecurity: Step 6 - Path is in allowed directory")

        // 7. 验证标准化后的路径是否与原始路径一致
        debugLog("validatePathSecurity: Step 7 - Comparing original and standardized paths...")
        if standardizedPath != url.path {
            debugLog("[FileTransferManager] Upload failed: Path contains relative references or symbolic links")
            debugLog("validatePathSecurity:   Original: \(url.path)")
            debugLog("validatePathSecurity:   Standardized: \(standardizedPath)")
            return false
        }
        debugLog("validatePathSecurity: Step 7 - Paths match")

        debugLog("validatePathSecurity: All security checks passed ✓")
        return true
    }
    
    private func performDownload(task: TransferTask, device: Device, fileItem: FileItem, shouldReplace: Bool) {
        // Capture destination path in a local variable to avoid accessing @MainActor class properties from background thread
        let destinationPath = task.destinationPath
        
        currentDownloadTask = task
        task.updateStatus(.transferring)
        
        // Validate destination path
        let destinationURL = URL(fileURLWithPath: destinationPath)
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
        if FileManager.default.fileExists(atPath: destinationPath) {
            if shouldReplace {
                // Remove existing file before download
                do {
                    try FileManager.default.removeItem(atPath: destinationPath)
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
        debugLog("Validating device connection before download...")
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
        debugLog("Starting download of file \(fileItem.name) (ID: \(fileItem.objectId))")
        debugLog("Download parameters:")
        debugLog("  File ID: \(fileItem.objectId)")
        debugLog("  Destination path: \(destinationPath)")
        debugLog("  Task ID: \(task.id.uuidString)")
        debugLog("  Should replace: \(shouldReplace)")

        let taskIdString = task.id.uuidString
        let objectId = fileItem.objectId

        debugLog("Step 1: Creating C strings manually")

        // Create C strings manually to avoid Swift 6 concurrency issues with withCString
        let destCStringArray = destinationPath.utf8CString
        let taskCStringArray = taskIdString.utf8CString

        debugLog("Step 2: Allocating memory for C strings")
        debugLog("  destCStringArray count: \(destCStringArray.count)")
        debugLog("  taskCStringArray count: \(taskCStringArray.count)")

        let mutableDest: UnsafeMutablePointer<CChar> = UnsafeMutablePointer.allocate(capacity: destCStringArray.count)
        let mutableTask: UnsafeMutablePointer<CChar> = UnsafeMutablePointer.allocate(capacity: taskCStringArray.count)

        debugLog("Step 3: Copying string contents to C pointers")

        for (index, byte) in destCStringArray.enumerated() {
            mutableDest.advanced(by: index).pointee = byte
        }
        for (index, byte) in taskCStringArray.enumerated() {
            mutableTask.advanced(by: index).pointee = byte
        }

        debugLog("Step 4: About to call Kalam_DownloadFile")
        debugLog("  objectId: \(objectId)")
        debugLog("  mutableDest: \(mutableDest)")
        debugLog("  mutableTask: \(mutableTask)")

        let downloadResult = Kalam_DownloadFile(objectId, mutableDest, mutableTask)

        debugLog("Step 5: Kalam_DownloadFile returned: \(downloadResult)")
        debugLog("Step 6: Deallocating C strings")

        mutableDest.deallocate()
        mutableTask.deallocate()

        debugLog("Step 7: C strings deallocated, result: \(downloadResult)")
        let result = downloadResult
        
        // Add a small delay to ensure file operations complete
        Thread.sleep(forTimeInterval: 0.5)
        
        if result > 0 {
            // Verify file was actually created and has content
            if let attributes = try? FileManager.default.attributesOfItem(atPath: destinationPath),
               let fileSize = attributes[.size] as? UInt64,
               fileSize > 0 {
                task.updateProgress(transferred: fileSize, speed: 0)
                task.updateStatus(.completed)
                debugLog("Download completed successfully: \(fileItem.name)")
            } else {
                // Check if file exists but is empty or corrupted
                if FileManager.default.fileExists(atPath: destinationPath) {
                    do {
                        try FileManager.default.removeItem(atPath: destinationPath)
                    } catch {
                        debugLog("Failed to remove corrupted file: \(error)")
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
        debugLog("========================================")
        debugLog("performUpload: Starting upload process")
        debugLog("========================================")
        debugLog("performUpload: Basic info:")
        debugLog("  Task ID: \(task.id.uuidString)")
        debugLog("  File name: \(task.fileName)")
        debugLog("  Source URL: \(sourceURL)")
        debugLog("  Source path: \(sourceURL.path)")
        debugLog("  ParentID: \(parentId)")
        debugLog("  StorageID: \(storageId)")
        debugLog("  Device: \(device.name)")
        debugLog("  Task status: \(task.status)")

        // Update status on main thread
        Task { @MainActor in
            task.updateStatus(.transferring)
        }

        debugLog("performUpload: Step 0 - Validating file...")
        guard let fileAttributes = try? FileManager.default.attributesOfItem(atPath: sourceURL.path),
              let fileSize = fileAttributes[.size] as? UInt64 else {
            Task { @MainActor in
                task.updateStatus(.failed(L10n.FileTransfer.cannotReadFileInfo))
            }
            debugLog("performUpload: ERROR - Failed to get file attributes for \(task.fileName)")
            debugLog("performUpload: Path: \(sourceURL.path)")
            moveTaskToCompleted(task)
            return
        }

        debugLog("performUpload: File attributes validated successfully")
        debugLog("performUpload:   File size: \(fileSize) bytes (\(fileSize / 1024) KB, \(fileSize / 1024 / 1024) MB)")
        debugLog("performUpload:   Creation date: \(fileAttributes[.creationDate] ?? "N/A")")
        debugLog("performUpload:   Modification date: \(fileAttributes[.modificationDate] ?? "N/A")")
        debugLog("performUpload:   Type: \(fileAttributes[.type] ?? "N/A")")

        if fileSize > 100 * 1024 * 1024 {
            debugLog("performUpload: WARNING - Large file detected (\(fileSize / 1024 / 1024)MB), upload may take time")
        }

        debugLog("performUpload: Step 0.5 - Checking task status...")
        if task.isCancelled {
            Task { @MainActor in
                task.updateStatus(.cancelled)
            }
            debugLog("performUpload: Task already cancelled, aborting upload")
            moveTaskToCompleted(task)
            return
        }
        debugLog("performUpload: Task status OK, proceeding with upload")

        // Perform upload using mutable C string pointers
        // Swift 6: Use defer blocks for automatic memory management
        debugLog("performUpload: Step 1 - Validating path encoding...")
        // Note: Swift String is always valid UTF-8, no validation needed
        debugLog("performUpload: Step 1 - Path validation passed (Swift String is always valid UTF-8)")

        // Create mutable C string copies before calling Go function
        debugLog("performUpload: Step 2 - Allocating C strings...")
        debugLog("performUpload:   Source path length: \(sourceURL.path.count) bytes")
        debugLog("performUpload:   Task ID length: \(task.id.uuidString.count) bytes")

        // Use utf8CString to get C string representation
        let sourceCStringArray = sourceURL.path.utf8CString
        let taskCStringArray = task.id.uuidString.utf8CString

        debugLog("performUpload:   Source C string array created")
        debugLog("performUpload:   Task C string array created")

        // Allocate memory manually
        let mutableSource: UnsafeMutablePointer<CChar> = UnsafeMutablePointer.allocate(capacity: sourceCStringArray.count)
        let mutableTask: UnsafeMutablePointer<CChar> = UnsafeMutablePointer.allocate(capacity: taskCStringArray.count)

        debugLog("performUpload:   Memory allocated for source: \(sourceCStringArray.count) bytes")
        debugLog("performUpload:   Memory allocated for task: \(taskCStringArray.count) bytes")

        // Copy string contents manually
        for (index, byte) in sourceCStringArray.enumerated() {
            mutableSource.advanced(by: index).pointee = byte
        }
        for (index, byte) in taskCStringArray.enumerated() {
            mutableTask.advanced(by: index).pointee = byte
        }

        debugLog("performUpload:   String contents copied")

        debugLog("performUpload: Step 2 - C strings allocated")
        debugLog("performUpload:   mutableSource pointer: \(mutableSource)")
        debugLog("performUpload:   mutableTask pointer: \(mutableTask)")

        // Ensure memory is deallocated at the end of this scope
        defer {
            debugLog("performUpload: Cleanup - Deallocating C strings...")
            mutableSource.deallocate()
            debugLog("performUpload:   mutableSource deallocated")
            mutableTask.deallocate()
            debugLog("performUpload:   mutableTask deallocated")
            debugLog("performUpload: Cleanup completed")
        }

        debugLog("performUpload: Step 3 - Calling Kalam_UploadFile...")
        debugLog("performUpload:   StorageID: \(storageId), ParentID: \(parentId)")
        debugLog("performUpload:   Calling Go function with C pointers...")

        let uploadResult = Kalam_UploadFile(storageId, parentId, mutableSource, mutableTask)

        debugLog("performUpload: Step 3 - Kalam_UploadFile returned")
        debugLog("performUpload:   Result: \(uploadResult) (1=success, 0=failure)")

        // Handle result on main thread
        Task { @MainActor in
            debugLog("performUpload: Step 4 - Processing upload result...")
            debugLog("performUpload:   Task cancelled: \(task.isCancelled)")
            debugLog("performUpload:   Upload result: \(uploadResult)")

            if task.isCancelled {
                task.updateStatus(.cancelled)
                debugLog("performUpload: Task was cancelled, skipping post-processing")
                self.moveTaskToCompleted(task)
                return
            }

            if uploadResult > 0 {
                debugLog("performUpload: Step 4.1 - Upload successful")
                task.updateProgress(transferred: fileSize, speed: 0)
                task.updateStatus(.completed)
                debugLog("performUpload: Upload completed successfully for \(task.fileName)")
            } else {
                debugLog("performUpload: Step 4.2 - Upload failed")
                task.updateStatus(.failed(L10n.FileTransfer.uploadFailed))
                debugLog("performUpload: Upload failed for \(task.fileName)")
                debugLog("performUpload: Checking device connection...")
                if let scanResult = Kalam_Scan() {
                    if strlen(scanResult) > 0 {
                        debugLog("performUpload: Device still connected")
                    } else {
                        debugLog("performUpload: Device disconnected")
                    }
                } else {
                    debugLog("performUpload: Scan returned nil, connection issue")
                }
            }

            debugLog("performUpload: Step 5 - Post-upload cleanup...")
            debugLog("performUpload:   Refreshing device storage (StorageID: \(storageId))...")
            let refreshResult = Kalam_RefreshStorage(storageId)
            debugLog("performUpload:   Refresh result: \(refreshResult)")
            if refreshResult > 0 {
                debugLog("performUpload:   Storage refreshed successfully")
            } else {
                debugLog("performUpload:   Failed to refresh storage")
            }

            debugLog("performUpload:   Resetting device cache...")
            let resetResult = Kalam_ResetDeviceCache()
            debugLog("performUpload:   Reset result: \(resetResult)")
            if resetResult > 0 {
                debugLog("performUpload:   Device cache reset successfully")
            } else {
                debugLog("performUpload:   Failed to reset device cache")
            }

            debugLog("performUpload:   Clearing FileSystemManager caches...")
            await FileSystemManager.shared.clearCache(for: device)
            await FileSystemManager.shared.forceClearCache()
            debugLog("performUpload:   Caches cleared")

            debugLog("performUpload:   Scheduling file list refresh notification...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                debugLog("performUpload:   Posting RefreshFileList notification")
                NotificationCenter.default.post(name: NSNotification.Name("RefreshFileList"), object: nil)
            }

            debugLog("performUpload: Step 6 - Moving task to completed list")
            self.moveTaskToCompleted(task)
            debugLog("performUpload: Upload process completed for \(task.fileName)")
        }
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
        debugLog("Progress callbacks disabled for download stability")
    }
    
    private func startTaskTracking() {
        // Optional: periodic cleanup or monitoring
    }
    
    private func stopTaskTracking() {
        taskTrackingTimer?.invalidate()
        taskTrackingTimer = nil
    }
}
