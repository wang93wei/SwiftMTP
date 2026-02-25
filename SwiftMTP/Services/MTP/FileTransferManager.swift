
import Foundation
import Combine
import Darwin

class FileTransferManager: ObservableObject {
    static let shared = FileTransferManager()
    
    @Published var activeTasks: [TransferTask] = []
    @Published var completedTasks: [TransferTask] = []
    
    private let transferQueue = DispatchQueue(label: "com.swiftmtp.transfer", qos: .userInitiated)
    private var _currentDownloadTask: TransferTask?
    private let taskLock = NSLock()
    
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
    }
    
    deinit {
    }
    
    
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
        
        guard !sourceURL.path.isEmpty else {
            return
        }
        
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            return
        }
        
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory)
        if isDirectory.boolValue {
            return
        }
        
        guard let fileAttributes = try? FileManager.default.attributesOfItem(atPath: sourceURL.path),
              let fileSize = fileAttributes[.size] as? UInt64 else {
            return
        }
        
        let maxFileSize: UInt64 = 10 * 1024 * 1024 * 1024
        guard fileSize <= maxFileSize else {
            return
        }
        
        guard validatePathSecurity(sourceURL) else {
            return
        }
        
        guard let storage = device.storageInfo.first(where: { $0.storageId == storageId }) else {
            return
        }
        
        if fileSize > storage.freeSpace {
            return
        }
        
        
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

        }
    }

    func clearCompletedTasks() {
    completedTasks.removeAll()
}

    
    
    private func validatePathSecurity(_ url: URL) -> Bool {

        let maxPathLength = 4096
        let pathLength = url.path.count
        guard pathLength <= maxPathLength else {
            return false
        }

        let standardizedPath = url.standardizedFileURL.path

        let pathComponents = standardizedPath.split(separator: "/")
        let dangerousPatterns = ["..", "%2e%2e", "%2E%2E"]
        for component in pathComponents {
            for pattern in dangerousPatterns {
                if component.lowercased().contains(pattern.lowercased()) {
                    return false
                }
            }
        }

        let dangerousChars = CharacterSet(charactersIn: "\u{0000}\n\r\t")
        if standardizedPath.rangeOfCharacter(from: dangerousChars) != nil {
            return false
        }

        do {
            let fileAttributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let fileType = fileAttributes[.type] as? FileAttributeType,
               fileType == .typeSymbolicLink {
                return false
            }
        } catch {
            return false
        }

        if standardizedPath != url.path {
            return false
        }

        return true
    }
    
    private func performDownload(task: TransferTask, device: Device, fileItem: FileItem, shouldReplace: Bool) {
        let destinationPath = task.destinationPath
        
        currentDownloadTask = task
        task.updateStatus(.transferring)
        
        let destinationURL = URL(fileURLWithPath: destinationPath)
        let destinationDir = destinationURL.deletingLastPathComponent()
        
        do {
            try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)
        } catch {
            DispatchQueue.main.async {
                task.updateStatus(.failed(L10n.FileTransfer.cannotCreateDirectory.localized(error.localizedDescription)))
            }
            moveTaskToCompleted(task)
            return
        }
        
        if FileManager.default.fileExists(atPath: destinationPath) {
            if shouldReplace {
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
        

        let taskIdString = task.id.uuidString
        let objectId = fileItem.objectId

        let destCStringArray = destinationPath.utf8CString
        let taskCStringArray = taskIdString.utf8CString

        let mutableDest: UnsafeMutablePointer<CChar> = UnsafeMutablePointer.allocate(capacity: destCStringArray.count)
        let mutableTask: UnsafeMutablePointer<CChar> = UnsafeMutablePointer.allocate(capacity: taskCStringArray.count)

        for (index, byte) in destCStringArray.enumerated() {
            mutableDest.advanced(by: index).pointee = byte
        }
        for (index, byte) in taskCStringArray.enumerated() {
            mutableTask.advanced(by: index).pointee = byte
        }

        let downloadResult = Kalam_DownloadFile(objectId, mutableDest, mutableTask)

        mutableDest.deallocate()
        mutableTask.deallocate()

        let result = downloadResult
        
        Thread.sleep(forTimeInterval: 0.5)
        
        if result > 0 {
            if let attributes = try? FileManager.default.attributesOfItem(atPath: destinationPath),
               let fileSize = attributes[.size] as? UInt64,
               fileSize > 0 {
                task.updateProgress(transferred: fileSize, speed: 0)
                task.updateStatus(.completed)
            } else {
                if FileManager.default.fileExists(atPath: destinationPath) {
                    do {
                        try FileManager.default.removeItem(atPath: destinationPath)
                    } catch {
                    }
                }
                task.updateStatus(.failed(L10n.FileTransfer.downloadedFileInvalidOrCorrupted))
            }
        } else {
            var errorMessage = L10n.FileTransfer.downloadFailed
            
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

        Task { @MainActor in
            task.updateStatus(.transferring)
        }

        guard let fileAttributes = try? FileManager.default.attributesOfItem(atPath: sourceURL.path),
              let fileSize = fileAttributes[.size] as? UInt64 else {
            Task { @MainActor in
                task.updateStatus(.failed(L10n.FileTransfer.cannotReadFileInfo))
            }
            moveTaskToCompleted(task)
            return
        }

        if fileSize > 100 * 1024 * 1024 {
        }

        if task.isCancelled {
            Task { @MainActor in
                task.updateStatus(.cancelled)
            }
            moveTaskToCompleted(task)
            return
        }

        let sourceCStringArray = sourceURL.path.utf8CString
        let taskCStringArray = task.id.uuidString.utf8CString

        let mutableSource: UnsafeMutablePointer<CChar> = UnsafeMutablePointer.allocate(capacity: sourceCStringArray.count)
        let mutableTask: UnsafeMutablePointer<CChar> = UnsafeMutablePointer.allocate(capacity: taskCStringArray.count)

        for (index, byte) in sourceCStringArray.enumerated() {
            mutableSource.advanced(by: index).pointee = byte
        }
        for (index, byte) in taskCStringArray.enumerated() {
            mutableTask.advanced(by: index).pointee = byte
        }

        defer {
            mutableSource.deallocate()
            mutableTask.deallocate()
        }

        let uploadResult = Kalam_UploadFile(storageId, parentId, mutableSource, mutableTask)

        Task { @MainActor in

            if task.isCancelled {
                task.updateStatus(.cancelled)
                self.moveTaskToCompleted(task)
                return
            }

            if uploadResult > 0 {
                task.updateProgress(transferred: fileSize, speed: 0)
                task.updateStatus(.completed)
            } else {
                task.updateStatus(.failed(L10n.FileTransfer.uploadFailed))
                if let scanResult = Kalam_Scan() {
                    if strlen(scanResult) > 0 {
                    } else {
                    }
                } else {
                }
            }

            let refreshResult = Kalam_RefreshStorage(storageId)
            if refreshResult > 0 {
            } else {
            }

            let resetResult = Kalam_ResetDeviceCache()
            if resetResult > 0 {
            } else {
            }

            await FileSystemManager.shared.clearCache(for: device)
            await FileSystemManager.shared.forceClearCache()

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                NotificationCenter.default.post(name: NSNotification.Name("RefreshFileList"), object: nil)
            }

            self.moveTaskToCompleted(task)
        }
    }
    
    func moveTaskToCompleted(_ task: TransferTask) {
        DispatchQueue.main.async {
            if self.completedTasks.contains(where: { $0.id == task.id }) {
                return
            }
            self.activeTasks.removeAll { $0.id == task.id }
            self.completedTasks.insert(task, at: 0)
        }
    }
    
    struct DirectoryUploadResult {
        let totalFiles: Int
        let uploadedFiles: Int
        let failedFiles: Int
        let skippedFiles: Int
        let errors: [String]
    }
    
    var directoryUploadCancelled = false
    let directoryUploadLock = NSLock()
    
}
