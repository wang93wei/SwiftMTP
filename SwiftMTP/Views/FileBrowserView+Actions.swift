import SwiftUI
import AppKit
import UniformTypeIdentifiers

extension FileBrowserView {
    func downloadFile(_ file: FileItem) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = file.name
        panel.canCreateDirectories = true

        panel.begin { response in
            if response == .OK, let url = panel.url {
                FileTransferManager.shared.downloadFile(from: device, fileItem: file, to: url, shouldReplace: true)
            }
        }
    }
    
    func downloadSelectedFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = L10n.FileBrowser.chooseDownloadLocation

        LanguageManager.ensureAppleLanguages()

        panel.begin { response in
            if response == .OK, let directory = panel.url {
                let filesToDownload = currentFiles.filter { selectedFiles.contains($0.id) && !$0.isDirectory }
                
                let existingFiles = filesToDownload.filter { file in
                    let destination = directory.appendingPathComponent(file.name)
                    return FileManager.default.fileExists(atPath: destination.path)
                }
                
                if !existingFiles.isEmpty {
                    let alert = NSAlert()
                    alert.messageText = L10n.FileBrowser.someFilesAlreadyExist
                    alert.informativeText = L10n.FileBrowser.filesAlreadyExistMessage.localized(
                        existingFiles.count,
                        existingFiles.map { "• \($0.name)" }.joined(separator: "\n")
                    )
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: L10n.FileBrowser.cancel)
                    alert.addButton(withTitle: L10n.FileBrowser.skipExistingFiles)
                    alert.addButton(withTitle: L10n.FileBrowser.replaceAll)
                    
                    if let window = NSApp.keyWindow {
                        alert.beginSheetModal(for: window) { response in
                            switch response {
                            case .alertSecondButtonReturn:
                                let filesToActuallyDownload = filesToDownload.filter { file in
                                    let destination = directory.appendingPathComponent(file.name)
                                    return !FileManager.default.fileExists(atPath: destination.path)
                                }
                                for file in filesToActuallyDownload {
                                    let destination = directory.appendingPathComponent(file.name)
                                    FileTransferManager.shared.downloadFile(from: device, fileItem: file, to: destination)
                                }
                            case .alertThirdButtonReturn:
                                for file in filesToDownload {
                                    let destination = directory.appendingPathComponent(file.name)
                                    FileTransferManager.shared.downloadFile(from: device, fileItem: file, to: destination, shouldReplace: true)
                                }
                            default:
                                break
                            }
                        }
                    } else {
                        let response = alert.runModal()
                        switch response {
                        case .alertSecondButtonReturn:
                            let filesToActuallyDownload = filesToDownload.filter { file in
                                let destination = directory.appendingPathComponent(file.name)
                                return !FileManager.default.fileExists(atPath: destination.path)
                            }
                            for file in filesToActuallyDownload {
                                let destination = directory.appendingPathComponent(file.name)
                                FileTransferManager.shared.downloadFile(from: device, fileItem: file, to: destination)
                            }
                        case .alertThirdButtonReturn:
                            for file in filesToDownload {
                                let destination = directory.appendingPathComponent(file.name)
                                FileTransferManager.shared.downloadFile(from: device, fileItem: file, to: destination, shouldReplace: true)
                            }
                        default:
                            break
                        }
                    }
                } else {
                    for file in filesToDownload {
                        let destination = directory.appendingPathComponent(file.name)
                        FileTransferManager.shared.downloadFile(from: device, fileItem: file, to: destination)
                    }
                }
            }
        }
    }
    

    func checkFileExists(_ fileName: String, parentId: UInt32) -> FileItem? {
        let existingFile = currentFiles.first { $0.name == fileName && !$0.isDirectory }
        if existingFile != nil {
        }
        return existingFile
    }

    func showFileReplaceDialog(existingFiles: [(url: URL, existingFile: FileItem)], completion: @escaping ([(url: URL, shouldReplace: Bool)]) -> Void) {

        let alert = NSAlert()
        alert.messageText = L10n.FileBrowser.someFilesAlreadyExist
        alert.informativeText = L10n.FileBrowser.filesAlreadyExistMessage.localized(
            existingFiles.count,
            existingFiles.map { "• \($0.url.lastPathComponent)" }.joined(separator: "\n")
        )
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.FileBrowser.cancel)
        alert.addButton(withTitle: L10n.FileBrowser.skipExistingFiles)
        alert.addButton(withTitle: L10n.FileBrowser.replaceAll)

        let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first

        if let window = window {
            alert.beginSheetModal(for: window) { response in
                switch response {
                case .alertSecondButtonReturn:
                    let filesToUpload = existingFiles.map { ($0.url, false) }
                    completion(filesToUpload)
                case .alertThirdButtonReturn:
                    let filesToUpload = existingFiles.map { ($0.url, true) }
                    completion(filesToUpload)
                default:
                    completion([])
                }
            }
        } else {
            completion([])
        }
    }

    func processUploadFiles(_ files: [(url: URL, parentId: UInt32, storageId: UInt32)]) {

        var existingFiles: [(url: URL, existingFile: FileItem)] = []
        var newFiles: [(url: URL, parentId: UInt32, storageId: UInt32)] = []

        for file in files {
            if let existingFile = checkFileExists(file.url.lastPathComponent, parentId: file.parentId) {
                existingFiles.append((url: file.url, existingFile: existingFile))
            } else {
                newFiles.append(file)
            }
        }

        if existingFiles.isEmpty {
            for file in newFiles {
                FileTransferManager.shared.uploadFile(to: device, sourceURL: file.url, parentId: file.parentId, storageId: file.storageId)
            }
            return
        }

        showFileReplaceDialog(existingFiles: existingFiles) { decision in
            for file in newFiles {
                FileTransferManager.shared.uploadFile(to: device, sourceURL: file.url, parentId: file.parentId, storageId: file.storageId)
            }

            for (url, shouldReplace) in decision {
                if shouldReplace {
                    let file = files.first { $0.url == url }!
                    FileTransferManager.shared.uploadFile(to: device, sourceURL: file.url, parentId: file.parentId, storageId: file.storageId)
                }
            }
        }
    }

    func selectFilesToUpload() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true

        LanguageManager.ensureAppleLanguages()

        panel.begin { response in
            if response == .OK {
                let parentId = currentPath.last?.objectId ?? AppConfiguration.rootDirectoryId

                let storageId: UInt32
                if let pathStorageId = currentPath.first?.storageId {
                    storageId = pathStorageId
                } else if let firstStorage = device.storageInfo.first {
                    storageId = firstStorage.storageId
                } else {
                    return
                }

                let filesToUpload = panel.urls.map { (url: $0, parentId: parentId, storageId: storageId) }
                processUploadFiles(filesToUpload)
            }
        }
    }
    
    func selectDirectoryToUpload() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = L10n.FileBrowser.selectUploadFolder
        
        LanguageManager.ensureAppleLanguages()
        
        panel.begin { response in
            if response == .OK, let directoryURL = panel.url {
                let parentId = self.currentPath.last?.objectId ?? AppConfiguration.rootDirectoryId
                let storageId: UInt32
                if let pathStorageId = self.currentPath.first?.storageId {
                    storageId = pathStorageId
                } else if let firstStorage = self.device.storageInfo.first {
                    storageId = firstStorage.storageId
                } else {
                    return
                }
                
                
                Task {
                    await self.uploadDirectoryWithProgress(
                        directoryURL: directoryURL,
                        parentId: parentId,
                        storageId: storageId
                    )
                }
            }
        }
    }
    
    @MainActor
    func uploadDirectoryWithProgress(
        directoryURL: URL,
        parentId: UInt32,
        storageId: UInt32
    ) async {

        let result = await FileTransferManager.shared.uploadDirectory(
            to: self.device,
            sourceURL: directoryURL,
            parentId: parentId,
            storageId: storageId
        ) { completed, total in
            let progress = Double(completed) / Double(total) * 100
        }

        if result.failedFiles == 0 {
            ToastManager.shared.showSuccess(
                title: L10n.FileBrowser.uploadSuccess,
                message: L10n.FileBrowser.uploadDirectorySuccess.localized(
                    result.uploadedFiles,
                    directoryURL.lastPathComponent
                )
            )
        } else if result.uploadedFiles == 0 {
            ToastManager.shared.showError(
                title: L10n.FileBrowser.uploadFailed,
                message: L10n.FileBrowser.uploadDirectoryFailed.localized(
                    result.failedFiles,
                    result.errors.first ?? "Unknown error"
                )
            )
        } else {
            let message = L10n.FileBrowser.uploadDirectoryPartial.localized(
                result.uploadedFiles,
                result.totalFiles
            )
            let errorDetails = result.errors.isEmpty ? "" : result.errors.prefix(3).joined(separator: "\n")
            ToastManager.shared.showWarning(
                title: message,
                message: errorDetails.isEmpty ? nil : errorDetails + (result.errors.count > 3 ? "\n..." : "")
            )
        }
    }
    
    func deleteFile(_ file: FileItem) {
        Task {
            let result = Kalam_DeleteObject(file.objectId)
            let success = result > 0

            if success {
                await FileSystemManager.shared.clearCache(for: device)
                await loadFiles()
            } else {
                errorMessage = L10n.FileBrowser.operationFailedWithMessage.localized(file.name)
                showingErrorAlert = true
            }
        }
    }
    
    func deleteSelectedFiles() {
        let filesToDelete = currentFiles.filter { selectedFiles.contains($0.id) }
        
        guard !filesToDelete.isEmpty else {
            return
        }
        
        let fileNames = filesToDelete.map { $0.name }.joined(separator: "、")
        let alertTitle = filesToDelete.count == 1 ? L10n.FileBrowser.deleteFile : L10n.FileBrowser.deleteMultipleFiles
        let alertMessage = filesToDelete.count == 1
            ? L10n.FileBrowser.confirmDeleteFileWithName.localized(filesToDelete.first!.name)
            : L10n.FileBrowser.confirmDeleteMultipleFiles.localized(filesToDelete.count, fileNames)
        
        let alert = NSAlert()
        alert.messageText = alertTitle
        alert.informativeText = alertMessage
        alert.alertStyle = .critical
        alert.addButton(withTitle: L10n.FileBrowser.cancel)
        alert.addButton(withTitle: L10n.FileBrowser.delete)
        
        if let window = NSApp.keyWindow {
            alert.beginSheetModal(for: window) { response in
                if response == .alertSecondButtonReturn {
                    performBatchDelete(files: filesToDelete)
                }
            }
        } else {
            let response = alert.runModal()
            if response == .alertSecondButtonReturn {
                performBatchDelete(files: filesToDelete)
            }
        }
    }
    
    func performBatchDelete(files: [FileItem]) {
    Task {
        var deletedCount = 0
        var failedFiles: [String] = []

        for file in files {
            let result = Kalam_DeleteObject(file.objectId)
            if result > 0 {
                deletedCount += 1
            } else {
                failedFiles.append(file.name)
            }
        }

        await FileSystemManager.shared.clearCache(for: device)
        await loadFiles()

        if failedFiles.isEmpty {
        } else {
            errorMessage = "The following files failed to delete:\n\n\(failedFiles.joined(separator: "\n"))"
            showingErrorAlert = true
        }

        selectedFiles.removeAll()
    }
}
    
    
}
