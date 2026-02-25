import SwiftUI
import AppKit
import UniformTypeIdentifiers

extension FileBrowserView {
    var refreshButton: some View {
        Button {
            NotificationCenter.default.post(name: NSNotification.Name("RefreshFileList"), object: nil)
        } label: {
            Label(L10n.MainWindow.refresh, systemImage: "arrow.clockwise")
                .labelStyle(.iconOnly)
        }
        .help(L10n.MainWindow.refreshFileList)
        .glassEffect()
    }
    
    var transferTasksButton: some View {
        Button {
            showTransferPanel.toggle()
        } label: {
            Label(L10n.MainWindow.transferTasks, systemImage: "arrow.up.arrow.down.circle")
                .labelStyle(.iconOnly)
        }
        .help(L10n.MainWindow.viewTransferTasks)
        .glassEffect()
        .badge(transferManager.activeTasks.count)
    }
    
    var newFolderButton: some View {
        Button(L10n.FileBrowser.newFolder, systemImage: "folder.badge.plus") {
            showingCreateFolderDialog = true
        }
        .help(L10n.FileBrowser.createNewFolderHelp)
        .glassEffect()
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
        .glassEffect()
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
        .glassEffect()
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
        .glassEffect()
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
        .glassEffect()
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

    let parentId = currentPath.last?.objectId ?? AppConfiguration.rootDirectoryId
    let storageId = currentPath.first?.storageId ?? device.storageInfo.first?.storageId ?? AppConfiguration.rootDirectoryId

    Task {
        let result = folderName.withCString { cString in
            Kalam_CreateFolder(storageId, parentId, UnsafeMutablePointer(mutating: cString))
        }
        let success = result > 0

        if success {
            await FileSystemManager.shared.clearCache(for: device)
            await loadFiles()
            showingCreateFolderDialog = false
            newFolderName = ""
        } else {
        }
    }
}
    
    
    func handleDroppedFiles(_ providers: [NSItemProvider]) -> Bool {
        guard !currentPath.isEmpty || device.storageInfo.first != nil else {
            return false
        }
        
        let parentId = currentPath.last?.objectId ?? AppConfiguration.rootDirectoryId
        let storageId = currentPath.first?.storageId ?? device.storageInfo.first?.storageId ?? AppConfiguration.rootDirectoryId
        
        var fileURLs: [URL] = []
        let dispatchGroup = DispatchGroup()
        
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                dispatchGroup.enter()
                provider.loadObject(ofClass: URL.self) { url, error in
                    defer {
                        dispatchGroup.leave()
                    }
                    
                    if let error = error {
                        return
                    }
                    
                    if let url = url as? URL {
                        fileURLs.append(url)
                    }
                }
            }
        }
        
        dispatchGroup.notify(queue: .main) {
            
            if fileURLs.isEmpty {
                return
            }
            
            self.uploadDroppedFiles(fileURLs, parentId: parentId, storageId: storageId)
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
            Task {
                await uploadDirectoryWithProgress(
                    directoryURL: directoryURL,
                    parentId: parentId,
                    storageId: storageId
                )
            }
        }
    }
}
