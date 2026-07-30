import SwiftUI
import AppKit
import UniformTypeIdentifiers

private nonisolated final class DroppedFileURLCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []

    func append(_ url: URL) {
        lock.withLock {
            urls.append(url)
        }
    }

    func snapshot() -> [URL] {
        lock.withLock { urls }
    }
}

extension FileBrowserView {
    var refreshButton: some View {
        Button {
            Task {
                await FileSystemManager.shared.clearCache(for: device)
                await loadFiles()
            }
        } label: {
            Label(L10n.MainWindow.refresh, systemImage: "arrow.clockwise")
                .labelStyle(.iconOnly)
        }
        .help(L10n.MainWindow.refreshFileList)
    }
    
    var transferTasksButton: some View {
        Button {
            showTransferPanel.toggle()
        } label: {
            Label(L10n.MainWindow.transferTasks, systemImage: "arrow.up.arrow.down.circle")
                .labelStyle(.iconOnly)
        }
        .help(L10n.MainWindow.viewTransferTasks)
        .badge(transferManager.activeTasks.count)
    }
    
    var newFolderButton: some View {
        Button(L10n.FileBrowser.newFolder, systemImage: "folder.badge.plus") {
            showingCreateFolderDialog = true
        }
        .help(L10n.FileBrowser.createNewFolderHelp)
    }
    
    var uploadFilesButton: some View {
        Menu {
            Button {
                selectFilesToUpload()
            } label: {
                Label(L10n.FileBrowser.uploadFiles, systemImage: "doc")
            }
            
            Button {
                selectDirectoryToUpload()
            } label: {
                Label(L10n.FileBrowser.uploadFolder, systemImage: "folder")
            }
        } label: {
            Label(L10n.FileBrowser.uploadFiles, systemImage: "square.and.arrow.up")
        }
        .help(L10n.FileBrowser.uploadFilesHelp)
    }
    
    var downloadButton: some View {
        Button {
            downloadSelectedFiles()
        } label: {
            Label(L10n.FileBrowser.download, systemImage: "arrow.down.circle")
                .labelStyle(.iconOnly)
        }
        .help(L10n.FileBrowser.downloadHelp)
        .disabled(!hasDownloadableFiles)
    }
    
    var deleteButton: some View {
        Button {
            deleteSelectedFiles()
        } label: {
            Label(L10n.FileBrowser.deleteFile, systemImage: "trash")
                .labelStyle(.iconOnly)
        }
        .help(L10n.FileBrowser.deleteHelp)
        .disabled(selectedFiles.isEmpty)
        .tint(selectedFiles.isEmpty ? .secondary : .red)
    }

    var sortMenu: some View {
        Menu {
            Section {
                ForEach(SortOption.allCases, id: \.self) { option in
                    Button {
                        if sortOption == option {
                            sortAscending.toggle()
                        } else {
                            sortOption = option
                            sortAscending = true
                        }
                        Task {
                            await loadFiles()
                        }
                    } label: {
                        HStack {
                            Text(option.displayName)
                            Spacer()
                            if sortOption == option {
                                Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                            }
                        }
                    }
                }
            }
        } label: {
            Label(L10n.FileBrowser.sort, systemImage: "arrow.up.arrow.down")
                .labelStyle(.iconOnly)
        }
        .help(L10n.FileBrowser.sortFiles)
    }

    
    var createFolderDialog: some View {
        VStack(spacing: 16) {
            Text(L10n.FileBrowser.createNewFolderDialog)
                .font(.headline)

            TextField(L10n.FileBrowser.folderNamePlaceholder, text: $newFolderName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)

            HStack(spacing: 12) {
                Button(L10n.FileBrowser.cancel) {
                    showingCreateFolderDialog = false
                    newFolderName = ""
                }
                .keyboardShortcut(.cancelAction)

                Button(L10n.FileBrowser.create) {
                    createFolder()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 350)
        .onDrop(of: [.fileURL], delegate: RejectDropDelegate())
    }
    
    func createFolder() {
    let folderName = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !folderName.isEmpty else { return }

    Task {
        do {
            try await FileSystemManager.shared.createFolder(
                for: device,
                parent: currentPath.last,
                name: folderName
            )
            await loadFiles()
            showingCreateFolderDialog = false
            newFolderName = ""
        } catch {
            errorMessage = String(describing: error)
            showingErrorAlert = true
        }
    }
}
    
    
    func handleDroppedFiles(_ providers: [NSItemProvider]) -> Bool {
        guard !currentPath.isEmpty || device.storageInfo.first != nil else {
            return false
        }
        
        let parentId = currentPath.last?.objectId ?? AppConfiguration.rootDirectoryId
        guard let storageId = currentPath.first?.storageId ?? device.storageInfo.first?.storageId else {
            return false
        }
        
        let fileURLs = DroppedFileURLCollector()
        let dispatchGroup = DispatchGroup()
        
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                dispatchGroup.enter()
                _ = provider.loadObject(ofClass: URL.self) { url, error in
                    defer {
                        dispatchGroup.leave()
                    }
                    
                    guard error == nil, let url else {
                        return
                    }
                    
                    fileURLs.append(url)
                }
            }
        }
        
        dispatchGroup.notify(queue: .main) {
            let urls = fileURLs.snapshot()
            if urls.isEmpty {
                return
            }
            
            self.uploadDroppedFiles(urls, parentId: parentId, storageId: storageId)
        }
        
        return true
    }
    
    func uploadDroppedFiles(_ urls: [URL], parentId: UInt32, storageId: UInt32) {

        var filesToUpload: [(url: URL, parentId: UInt32, storageId: UInt32)] = []
        var directoriesToUpload: [URL] = []

        for url in urls {
            if url.lastPathComponent.hasPrefix(".") {
                continue
            }
            
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            
            if exists && isDirectory.boolValue {
                directoriesToUpload.append(url)
            } else {
                filesToUpload.append((url: url, parentId: parentId, storageId: storageId))
            }
        }

        if !filesToUpload.isEmpty {
            processUploadFiles(filesToUpload)
        }
        
        for directoryURL in directoriesToUpload {
            uploadDirectoryWithProgress(
                directoryURL: directoryURL,
                parentId: parentId,
                storageId: storageId
            )
        }
    }
}
