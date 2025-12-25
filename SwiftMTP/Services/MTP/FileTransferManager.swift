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
        task.isCancelled = true
        task.id.uuidString.withCString { cString in
            Kalam_CancelTask(UnsafeMutablePointer(mutating: cString))
        }
        task.updateStatus(.cancelled)
        moveTaskToCompleted(task)
    }
    
    func clearCompletedTasks() {
        DispatchQueue.main.async {
            self.completedTasks.removeAll()
        }
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
