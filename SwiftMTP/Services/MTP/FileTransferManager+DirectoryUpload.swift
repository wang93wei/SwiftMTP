import Foundation
import Darwin

extension FileTransferManager {
    private func isDirectoryUploadCancelled() -> Bool {
        directoryUploadLock.lock()
        defer { directoryUploadLock.unlock() }
        return directoryUploadCancelled
    }
    
    func cancelDirectoryUpload() {
        directoryUploadLock.lock()
        defer { directoryUploadLock.unlock() }
        directoryUploadCancelled = true
    }
    
    private func resetDirectoryUploadCancel() {
        directoryUploadLock.lock()
        defer { directoryUploadLock.unlock() }
        directoryUploadCancelled = false
    }
    
    func uploadDirectory(
        to device: Device,
        sourceURL: URL,
        parentId: UInt32,
        storageId: UInt32,
        progressHandler: ((Int, Int) -> Void)? = nil
    ) async -> DirectoryUploadResult {
        resetDirectoryUploadCancel()
        
        let filesToUpload = collectFilesInDirectory(sourceURL)
        
        guard !filesToUpload.isEmpty else {
            return DirectoryUploadResult(totalFiles: 0, uploadedFiles: 0, failedFiles: 0, skippedFiles: 0, errors: ["No files found in directory"])
        }
        
        let totalSize: UInt64 = filesToUpload.reduce(0) { sum, url in
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
            return sum + fileSize
        }
        
        if let storage = device.storageInfo.first(where: { $0.storageId == storageId }) {
            if totalSize > storage.freeSpace {
                let needed = FileItem.formatFileSize(totalSize)
                let available = FileItem.formatFileSize(storage.freeSpace)
                return DirectoryUploadResult(
                    totalFiles: filesToUpload.count,
                    uploadedFiles: 0,
                    failedFiles: filesToUpload.count,
                    skippedFiles: 0,
                    errors: ["Insufficient storage space: needed \(needed), available \(available)"]
                )
            }
        }
        
        let directoryTask = TransferTask(
            type: .upload,
            fileName: "📁 \(sourceURL.lastPathComponent)",
            sourceURL: sourceURL,
            destinationPath: "/device/\(parentId)",
            totalSize: totalSize
        )
        
        await MainActor.run {
            self.activeTasks.append(directoryTask)
            directoryTask.updateStatus(TransferStatus.transferring)
        }
        
        let dirName = sourceURL.lastPathComponent
        let targetFolderId = await getOrCreateFolder(
            device: device,
            folderName: dirName,
            parentId: parentId,
            storageId: storageId
        )
        
        guard targetFolderId != 0 else {
            let failStatus = TransferStatus.failed("Failed to create target folder: \(dirName)")
            await MainActor.run {
                directoryTask.updateStatus(failStatus)
                self.moveTaskToCompleted(directoryTask)
            }
            return DirectoryUploadResult(
                totalFiles: filesToUpload.count,
                uploadedFiles: 0,
                failedFiles: filesToUpload.count,
                skippedFiles: 0,
                errors: ["Failed to create target folder: \(dirName)"]
            )
        }
        
        
        var uploadedCount = 0
        var failedCount = 0
        var skippedCount = 0
        var errors: [String] = []
        var totalTransferred: UInt64 = 0
        
        let basePath = sourceURL.path
        var folderCache: [String: UInt32] = [:]
        
        for (index, fileURL) in filesToUpload.enumerated() {
            if isDirectoryUploadCancelled() || directoryTask.isCancelled {
                skippedCount = filesToUpload.count - index
                errors.append("Upload cancelled by user")
                break
            }
            
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? UInt64) ?? 0
            
            if let storage = device.storageInfo.first(where: { $0.storageId == storageId }) {
                let remainingSpace = storage.freeSpace > totalTransferred ? storage.freeSpace - totalTransferred : 0
                if fileSize > remainingSpace {
                    let needed = FileItem.formatFileSize(fileSize)
                    let available = FileItem.formatFileSize(remainingSpace)
                    failedCount += 1
                    errors.append("Insufficient storage for \(fileURL.lastPathComponent): needed \(needed), available \(available)")
                    continue
                }
            }
            
            guard let relativePath = getRelativePath(from: basePath, to: fileURL.path) else {
                failedCount += 1
                errors.append("Failed to get relative path: \(fileURL.lastPathComponent)")
                continue
            }
            
            let subFolderId = await createSubdirectoryStructure(
                device: device,
                relativePath: relativePath,
                baseFolderId: targetFolderId,
                storageId: storageId,
                folderCache: &folderCache
            )
            
            guard subFolderId != 0 else {
                failedCount += 1
                errors.append("Failed to create subdirectory: \(relativePath)")
                continue
            }
            
            let success = await performFileUploadWithoutTask(
                device: device,
                sourceURL: fileURL,
                parentId: subFolderId,
                storageId: storageId
            )
            
            if success {
                uploadedCount += 1
                totalTransferred += fileSize
            } else {
                failedCount += 1
                errors.append("Failed to upload: \(fileURL.lastPathComponent)")
            }
            
            await MainActor.run {
                directoryTask.updateProgress(transferred: totalTransferred, speed: 0)
            }
            
            progressHandler?(index + 1, filesToUpload.count)
        }
        
        let finalStatus: TransferStatus
        if isDirectoryUploadCancelled() || directoryTask.isCancelled {
            finalStatus = .cancelled
        } else if failedCount == 0 {
            finalStatus = .completed
        } else if uploadedCount == 0 {
            finalStatus = .failed("All files failed to upload")
        } else {
            finalStatus = .completed
        }
        
        await MainActor.run {
            directoryTask.updateStatus(finalStatus)
            self.moveTaskToCompleted(directoryTask)
        }
        
        let _ = Kalam_RefreshStorage(storageId)
        let _ = Kalam_ResetDeviceCache()
        await FileSystemManager.shared.clearCache(for: device)
        await FileSystemManager.shared.forceClearCache()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NotificationCenter.default.post(name: NSNotification.Name("RefreshFileList"), object: nil)
        }
        
        
        return DirectoryUploadResult(
            totalFiles: filesToUpload.count,
            uploadedFiles: uploadedCount,
            failedFiles: failedCount,
            skippedFiles: skippedCount,
            errors: errors
        )
    }
    
    private func collectFilesInDirectory(_ directoryURL: URL) -> [URL] {
        var files: [URL] = []
        let fileManager = FileManager.default
        
        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }
        
        for case let fileURL as URL in enumerator {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
                if resourceValues.isRegularFile == true {
                    files.append(fileURL)
                }
            } catch {
            }
        }
        
        return files
    }
    
    private func getRelativePath(from basePath: String, to targetPath: String) -> String? {
        guard targetPath.hasPrefix(basePath) else { return nil }
        
        let relativePath = String(targetPath.dropFirst(basePath.count))
        return relativePath.hasPrefix("/") ? String(relativePath.dropFirst()) : relativePath
    }
    
    private func getOrCreateFolder(
        device: Device,
        folderName: String,
        parentId: UInt32,
        storageId: UInt32
    ) async -> UInt32 {
        let files = await FileSystemManager.shared.getFileList(
            for: device,
            parentId: parentId,
            storageId: storageId
        )
        
        if let existingFolder = files.first(where: { $0.name == folderName && $0.isDirectory }) {
            return existingFolder.objectId
        }
        
        let result = folderName.withCString { cString in
            Kalam_CreateFolder(storageId, parentId, UnsafeMutablePointer(mutating: cString))
        }
        
        if result > 0 {
            await FileSystemManager.shared.clearCache(for: device)
            let updatedFiles = await FileSystemManager.shared.getFileList(
                for: device,
                parentId: parentId,
                storageId: storageId
            )
            if let newFolder = updatedFiles.first(where: { $0.name == folderName && $0.isDirectory }) {
                return newFolder.objectId
            }
            return UInt32(result)
        } else {
            return 0
        }
    }
    
    private func createSubdirectoryStructure(
        device: Device,
        relativePath: String,
        baseFolderId: UInt32,
        storageId: UInt32,
        folderCache: inout [String: UInt32]
    ) async -> UInt32 {
        let components = relativePath.split(separator: "/").dropLast().map(String.init)
        var currentParentId = baseFolderId
        var currentPath = ""
        
        for component in components {
            currentPath = currentPath.isEmpty ? String(component) : "\(currentPath)/\(component)"
            
            if let cachedId = folderCache[currentPath] {
                currentParentId = cachedId
                continue
            }
            
            let folderId = await getOrCreateFolder(
                device: device,
                folderName: component,
                parentId: currentParentId,
                storageId: storageId
            )
            
            guard folderId != 0 else {
                return 0
            }
            
            folderCache[currentPath] = folderId
            currentParentId = folderId
        }
        
        return currentParentId
    }
    
    
    private func performFileUploadWithoutTask(
        device: Device,
        sourceURL: URL,
        parentId: UInt32,
        storageId: UInt32
    ) async -> Bool {
        
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            return false
        }
        
        guard let fileAttributes = try? FileManager.default.attributesOfItem(atPath: sourceURL.path),
              let fileSize = fileAttributes[.size] as? UInt64 else {
            return false
        }
        
        if let storage = device.storageInfo.first(where: { $0.storageId == storageId }) {
            if fileSize > storage.freeSpace {
                return false
            }
        }
        
        let taskId = UUID().uuidString
        
        let sourceCStringArray = sourceURL.path.utf8CString
        let taskCStringArray = taskId.utf8CString
        
        let mutableSource: UnsafeMutablePointer<CChar> = UnsafeMutablePointer.allocate(capacity: sourceCStringArray.count)
        let mutableTask: UnsafeMutablePointer<CChar> = UnsafeMutablePointer.allocate(capacity: taskCStringArray.count)
        
        defer {
            mutableSource.deallocate()
            mutableTask.deallocate()
        }
        
        sourceCStringArray.withUnsafeBufferPointer { buffer in
            _ = strcpy(mutableSource, buffer.baseAddress!)
        }
        taskCStringArray.withUnsafeBufferPointer { buffer in
            _ = strcpy(mutableTask, buffer.baseAddress!)
        }
        
        let uploadResult = Kalam_UploadFile(storageId, parentId, mutableSource, mutableTask)
        
        
        return uploadResult > 0
    }
}
